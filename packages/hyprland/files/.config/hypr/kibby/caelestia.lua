-- Caelestia Shell bridge on top of the CachyOS Hyprland base.
-- Window management, workspaces, applications, and monitor rules remain host-owned.

local function replaceBind(keys, dispatcher, options)
    hl.unbind(keys)
    hl.bind(keys, dispatcher, options or {})
end

local colourPicker = hl.dsp.exec_cmd("hyprpicker -a -n -b -f hex")
local screenText = "{{HOME}}/.local/bin/kibby-screen-text"

hl.on("hyprland.start", function()
    -- Colours.qml cannot watch scheme.json when its parent state directory does
    -- not exist yet. Initialising the scheme first guarantees live >scheme
    -- changes are observed from the shell's first launch onward.
    hl.exec_cmd("caelestia scheme get -n >/dev/null && caelestia shell -d")
end)

-- Shell surfaces
replaceBind("SUPER + Space", hl.dsp.global("caelestia:launcher"),
    { description = "Caelestia: launcher" })
replaceBind("SUPER + X", hl.dsp.global("caelestia:sidebar"),
    { description = "Caelestia: sidebar" })
replaceBind("SUPER + A", hl.dsp.global("caelestia:sidebar"),
    { description = "Caelestia: notifications and sidebar" })
replaceBind("SUPER + Z", hl.dsp.global("caelestia:nexus"),
    { description = "Caelestia: settings" })
replaceBind("SUPER + K", hl.dsp.global("caelestia:showall"),
    { description = "Caelestia: dashboard overview" })
replaceBind("SUPER + ALT + C", hl.dsp.global("caelestia:session"),
    { description = "Caelestia: session menu" })
replaceBind("SUPER + L", hl.dsp.global("caelestia:lock"),
    { description = "Caelestia: lock" })

-- Preserve a fast window-cycle key without depending on a shell-specific switcher.
replaceBind("SUPER + Tab", hl.dsp.window.cycle_next(),
    { description = "Hyprland: cycle windows" })

-- The 2.4 GHz receiver remaps these buttons through keyd. USB and Bluetooth
-- expose the native side-button codes instead, so bind those to the same
-- previous/next workspace actions.
replaceBind("mouse:275", hl.dsp.focus({ workspace = "m-1" }),
    { mouse = true, description = "Hyprland: mouse back to previous workspace" })
replaceBind("mouse:276", hl.dsp.focus({ workspace = "m+1" }),
    { mouse = true, description = "Hyprland: mouse forward to next workspace" })


-- Pickers and capture
hl.unbind("SUPER + P")
replaceBind("SUPER + R", colourPicker,
    { description = "Colour picker: copy hex value" })
replaceBind("SUPER + SHIFT + X", hl.dsp.exec_cmd(screenText .. " ocr"),
    { description = "Screen text: OCR region to clipboard" })
replaceBind("SUPER + B", hl.dsp.exec_cmd(screenText .. " translate"),
    { description = "Screen text: OCR, translate, and copy" })
replaceBind("SUPER + V", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"),
    { description = "Caelestia: clipboard history" })
replaceBind("SUPER + period", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"),
    { description = "Caelestia: emoji picker" })
replaceBind("SUPER + SHIFT + W", hl.dsp.global("caelestia:wallpapers"),
    { description = "Caelestia: wallpaper switcher (press again to close)" })
replaceBind("Print", hl.dsp.exec_cmd("caelestia screenshot -r -f"),
    { locked = true, description = "Caelestia: frozen region screenshot" })
replaceBind("SUPER + Print", hl.dsp.exec_cmd("caelestia screenshot"),
    { locked = true, description = "Caelestia: full screenshot" })

-- Hardware keys. PipeWire changes are observed by Caelestia's OSD.
replaceBind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1.7 @DEFAULT_AUDIO_SINK@ 2%+"),
    { locked = true, repeating = true, description = "Audio: volume up (170% maximum)" })
replaceBind("XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),
    { locked = true, repeating = true, description = "Audio: volume down" })
replaceBind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, description = "Audio: toggle output mute" })
replaceBind("XF86AudioMicMute", hl.dsp.exec_cmd("{{HOME}}/.local/bin/kibby-mic-toggle"),
    { locked = true, description = "Audio: toggle microphone mute with notification" })

replaceBind("XF86AudioPlay", hl.dsp.global("caelestia:mediaToggle"),
    { locked = true, description = "Caelestia: play or pause media" })
replaceBind("XF86AudioPause", hl.dsp.global("caelestia:mediaToggle"),
    { locked = true, description = "Caelestia: play or pause media" })
replaceBind("XF86AudioNext", hl.dsp.global("caelestia:mediaNext"),
    { locked = true, description = "Caelestia: next media track" })
replaceBind("XF86AudioPrev", hl.dsp.global("caelestia:mediaPrev"),
    { locked = true, description = "Caelestia: previous media track" })
replaceBind("XF86MonBrightnessUp", hl.dsp.global("caelestia:brightnessUp"),
    { locked = true, repeating = true, description = "Caelestia: brightness up" })
replaceBind("XF86MonBrightnessDown", hl.dsp.global("caelestia:brightnessDown"),
    { locked = true, repeating = true, description = "Caelestia: brightness down" })
