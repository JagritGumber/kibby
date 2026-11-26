-- Kibby: each app keeps the volume set for it in a mixer, even when the app
-- sets its own.
--
-- WirePlumber's node/state-stream.lua remembers each app's stream volume and
-- puts it back when a new stream of that app appears. Some apps then set
-- their own volume over it, and that is remembered instead:
-- - A PulseAudio client that asks for a volume when it creates its stream gets
--   it applied by pipewire-pulse a moment after WirePlumber's restore, once the
--   stream's format is settled.
-- - Spotify 1.2.63 and later is reported to set its own volume again on its
--   stream when playback resumes or a track changes, ignoring the mixer.
--
-- Spotify 1.2.95 (Flatpak, watched on 2026-11-26) did neither. It kept one
-- stream across tracks and took the mixer's volume as its own (its MPRIS
-- Volume followed by the next track). Its stream after an ad came up at the
-- restored volume. Its video ads play through a second stream named
-- "Chromium", remembered under that name, so this guard cannot hold them. The
-- guard is therefore off unless KIBBY_APP_VOLUME_GUARD=required.
--
-- So for WINDOW_MS after such a moment (the stream appears with a remembered
-- volume, starts running again, is uncorked, or changes its media name), a
-- change away from the volume the stream had is taken as the app's own. It is
-- not remembered (this hook runs before node/store-stream-props and stops the
-- event), and the stream's volume is put back, once per change. Changes at any
-- other time, from a mixer or from the app, are kept and remembered as usual.

cutils = require ("common-utils")
log = Log.open_topic ("s-kibby-app-volume-guard")

-- An app sets its own volume within milliseconds of the moment (0.1 to 22 ms
-- in the test rig); a person at a mixer takes longer than a second.
WINDOW_MS = 1000
MAX_RESETS = 3

local state = State ("stream-properties")
local guards = {}

local function nowMs ()
  return GLib.get_monotonic_time () // 1000
end

-- The key node/state-stream.lua stores the stream under. Adapted from
-- formKey in WirePlumber's scripts/node/state-stream.lua
-- (Copyright © 2021-2022 Collabora Ltd., SPDX-License-Identifier: MIT).
local function formKey (properties)
  local class = (properties ["media.class"] or ""):gsub ("^Stream/", "")
  if properties ["media.role"] == "Notification" then
    return class .. ":media.role:Notification"
  end
  for _, k in ipairs ({ "application.id", "application.name", "media.name", "node.name" }) do
    local value = properties [k]
    if value then
      return string.format ("%s:%s:%s", class, k, value)
    end
  end
end

local function storedVolumes (key)
  local raw = state:load () [key]
  local json = raw and Json.Raw (raw)
  if not json or not json:is_object () then
    return nil
  end
  local stored = json:parse ()
  if stored.volume == nil and stored.channelVolumes == nil then
    return nil
  end
  return { volume = stored.volume, channelVolumes = stored.channelVolumes }
end

local function volumesOf (props)
  if props.volume == nil and props.channelVolumes == nil then
    return nil
  end
  local copy = props.channelVolumes and {} or nil
  for i, v in ipairs (props.channelVolumes or {}) do
    copy [i] = v
  end
  return { volume = props.volume, channelVolumes = copy }
end

local function close (a, b)
  return a ~= nil and b ~= nil and math.abs (a - b) < 0.001
end

local function sameVolumes (a, b)
  if a.channelVolumes and b.channelVolumes then
    if #a.channelVolumes ~= #b.channelVolumes then
      return false
    end
    for i, v in ipairs (a.channelVolumes) do
      if not close (v, b.channelVolumes [i]) then
        return false
      end
    end
  end
  if a.volume ~= nil and b.volume ~= nil and not close (a.volume, b.volume) then
    return false
  end
  return true
end

local function describe (volumes)
  return volumes.channelVolumes and table.concat (volumes.channelVolumes, ",") or tostring (volumes.volume)
end

local function putBack (node, volumes)
  local props = { "Spa:Pod:Object:Param:Props", "Props", volume = volumes.volume }
  if volumes.channelVolumes then
    local list = { "Spa:Float" }
    for _, v in ipairs (volumes.channelVolumes) do
      table.insert (list, v)
    end
    props.channelVolumes = Pod.Array (list)
  end
  node:set_param ("Props", Pod.Object (props))
end

local function arm (guard, why)
  if guard.current then
    guard.windowUntil = nowMs () + WINDOW_MS
    guard.resets = 0
    log:debug (string.format ("%s: guarding its volume for %d ms (%s)", guard.key, WINDOW_MS, why))
  end
end

-- An uncork or a new media name: moments an app may set its own volume again.
local function checkCues (guard, node)
  local properties = node.properties
  local corked = properties ["pulse.corked"] == "true"
  local mediaName = properties ["media.name"]
  if guard.corked and not corked then
    arm (guard, "uncorked")
  elseif mediaName ~= guard.mediaName then
    arm (guard, "media name changed")
  end
  guard.corked, guard.mediaName = corked, mediaName
end

local function restoring (properties)
  return Settings.get_boolean ("node.stream.restore-props") and properties ["state.restore-props"] ~= "false"
end

-- A new stream: track its volume, and guard it now if its app has one
-- remembered.
SimpleEventHook {
  name = "node/kibby-app-volume-guard-watch",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "matches", "Stream/*" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local properties = node.properties
    if not restoring (properties) then
      return
    end
    local key = formKey (properties)
    if not key then
      return
    end
    local guard = {
      key = key,
      current = storedVolumes (key),
      windowUntil = 0,
      resets = 0,
      pending = false,
      corked = properties ["pulse.corked"] == "true",
      mediaName = properties ["media.name"],
    }
    guards [node.id] = guard
    arm (guard, "new stream")
  end
}:register ()

-- PipeWire reuses node ids: a guard ends with its node. Guards are keyed by
-- node.id, the global id, because a removed node's proxy is no longer bound
-- and has no "bound-id" (as in WirePlumber's own node/software-dsp.lua).
SimpleEventHook {
  name = "node/kibby-app-volume-guard-forget",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-removed" },
      Constraint { "media.class", "matches", "Stream/*" },
    },
  },
  execute = function (event)
    guards [event:get_subject ().id] = nil
  end
}:register ()

-- Running again after idling (a resume) is a cue too.
SimpleEventHook {
  name = "node/kibby-app-volume-guard-state",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "matches", "Stream/*" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local guard = guards [node.id]
    if not guard then
      return
    end
    local props = event:get_properties ()
    if props ["event.subject.new-state"] == "running" and props ["event.subject.old-state"] ~= "running" then
      arm (guard, "running again")
    end
    checkCues (guard, node)
  end
}:register ()

-- Its volume changed. Inside a window, a change away from the stream's
-- volume is the app's own: it is never remembered, and the volume is put back
-- once per change (the node reports the app's volume until the put-back
-- lands). Outside a window, the change is the stream's new volume.
SimpleEventHook {
  name = "node/kibby-app-volume-guard",
  before = "node/store-stream-props",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-params-changed" },
      Constraint { "event.subject.param-id", "=", "Props" },
      Constraint { "media.class", "matches", "Stream/*" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local guard = guards [node.id]
    if not guard then
      return
    end
    if formKey (node.properties) ~= guard.key then
      guards [node.id] = nil
      return
    end
    checkCues (guard, node)
    for p in node:iterate_params ("Props") do
      local volumes = volumesOf (cutils.parseParam (p, "Props") or {})
      if volumes then
        if not guard.current or sameVolumes (volumes, guard.current) then
          guard.current = guard.current or volumes
          guard.pending = false
        elseif nowMs () < guard.windowUntil then
          event:stop_processing ()
          if not guard.pending and guard.resets < MAX_RESETS then
            guard.resets = guard.resets + 1
            guard.pending = true
            log:info (node, string.format ("%s set its own volume (%s); putting back %s",
                guard.key, describe (volumes), describe (guard.current)))
            putBack (node, guard.current)
          end
        else
          guard.current = volumes
          guard.pending = false
        end
      end
      break
    end
  end
}:register ()
