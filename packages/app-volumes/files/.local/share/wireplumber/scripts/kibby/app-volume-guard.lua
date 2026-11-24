-- Kibby: an app's remembered volume survives the app's own volume at start.
--
-- WirePlumber's node/state-stream.lua remembers each app's stream volume and
-- puts it back when a new stream of that app appears. A PulseAudio client that
-- asks for a volume when it creates its stream gets that volume applied by
-- pipewire-pulse a moment later, once the stream's format is settled. Spotify
-- does this for every track, at its own 100 %. So the restore is lost, and the
-- app's volume is then remembered in place of the one set in the mixer.
--
-- For GUARD_SECONDS after a stream with a remembered volume appears, a change
-- away from that volume is taken as the app's start-up override. It is not
-- remembered (this hook runs before node/store-stream-props and stops the
-- event), and the remembered volume is put back. Changes after that, from the
-- mixer or from the app itself, are kept and remembered as usual.

cutils = require ("common-utils")
log = Log.open_topic ("s-kibby-app-volume-guard")

GUARD_SECONDS = 2
MAX_RESETS = 3

local state = State ("stream-properties")
local guards = {}

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
  return stored
end

local function close (a, b)
  return a ~= nil and b ~= nil and math.abs (a - b) < 0.001
end

local function sameVolumes (props, stored)
  if stored.channelVolumes and props.channelVolumes then
    if #stored.channelVolumes ~= #props.channelVolumes then
      return false
    end
    for i, v in ipairs (stored.channelVolumes) do
      if not close (v, props.channelVolumes [i]) then
        return false
      end
    end
  end
  if stored.volume ~= nil and props.volume ~= nil and not close (stored.volume, props.volume) then
    return false
  end
  return true
end

local function putBack (node, stored)
  local props = { "Spa:Pod:Object:Param:Props", "Props", volume = stored.volume }
  if stored.channelVolumes then
    local volumes = { "Spa:Float" }
    for _, v in ipairs (stored.channelVolumes) do
      table.insert (volumes, v)
    end
    props.channelVolumes = Pod.Array (volumes)
  end
  node:set_param ("Props", Pod.Object (props))
end

-- A new stream: watch it for a moment if its app has a remembered volume.
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
    -- Nothing was restored, so there is nothing to keep.
    if not Settings.get_boolean ("node.stream.restore-props") or properties ["state.restore-props"] == "false" then
      return
    end
    local key = formKey (properties)
    local stored = key and storedVolumes (key)
    if not stored then
      return
    end
    local id = node ["bound-id"]
    local guard = { key = key, stored = stored, resets = 0, pending = false }
    guards [id] = guard
    Core.timeout_add (GUARD_SECONDS * 1000, function ()
      if guards [id] == guard then
        guards [id] = nil
      end
      return false
    end)
  end
}:register ()

-- PipeWire reuses node ids: a guard ends with its node.
SimpleEventHook {
  name = "node/kibby-app-volume-guard-forget",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-removed" },
      Constraint { "media.class", "matches", "Stream/*" },
    },
  },
  execute = function (event)
    guards [event:get_subject () ["bound-id"]] = nil
  end
}:register ()

-- Its volume changed: within the guard time, a change away from the
-- remembered volume is the app's override. It is never remembered, and it is
-- put back once per override (the node reports the app's volume until the
-- put-back lands).
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
    local id = node ["bound-id"]
    local guard = guards [id]
    if not guard then
      return
    end
    if formKey (node.properties) ~= guard.key then
      guards [id] = nil
      return
    end
    for p in node:iterate_params ("Props") do
      local props = cutils.parseParam (p, "Props")
      if props then
        if sameVolumes (props, guard.stored) then
          guard.pending = false
        else
          event:stop_processing ()
          if not guard.pending and guard.resets < MAX_RESETS then
            guard.resets = guard.resets + 1
            guard.pending = true
            log:info (node, string.format ("%s set its own volume at start (%s); putting back the remembered one (%s)",
                guard.key, props.channelVolumes and table.concat (props.channelVolumes, ",") or tostring (props.volume),
                guard.stored.channelVolumes and table.concat (guard.stored.channelVolumes, ",") or tostring (guard.stored.volume)))
            putBack (node, guard.stored)
          end
        end
      end
      break
    end
  end
}:register ()
