-- Generated from user-owned Kibby foundation source.

local function replaceBind(keys, dispatcher, options)
    hl.unbind(keys)
    hl.bind(keys, dispatcher, options or {})
end

replaceBind("SUPER + Return", hl.dsp.exec_cmd("{{terminal}}"),
    { description = "Kibby foundation: terminal" })
replaceBind("SUPER + Space", hl.dsp.exec_cmd("{{launcher}}"),
    { description = "Kibby foundation: launcher" })
replaceBind("SUPER + L", hl.dsp.exec_cmd("{{lock}} -c {{hyprlock_config}}"),
    { description = "Kibby foundation: lock" })
replaceBind("SUPER + CONTROL + Return",
    hl.dsp.exec_cmd("{{terminal}} -e sh -lc 'kibby doctor; exec \\\"${SHELL:-/bin/sh}\\\"'"),
    { description = "Kibby foundation: recovery terminal" })

replaceBind("XF86AudioRaiseVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ {{volume_step}}%+ -l 1.0"),
    { locked = true, repeating = true, description = "Kibby foundation: volume up" })
replaceBind("XF86AudioLowerVolume",
    hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ {{volume_step}}%-"),
    { locked = true, repeating = true, description = "Kibby foundation: volume down" })
replaceBind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true, description = "Kibby foundation: output mute" })
replaceBind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true, description = "Kibby foundation: microphone mute" })

replaceBind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set {{brightness_step}}%+"),
    { locked = true, repeating = true, description = "Kibby foundation: brightness up" })
replaceBind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set {{brightness_step}}%-"),
    { locked = true, repeating = true, description = "Kibby foundation: brightness down" })

replaceBind("Print", hl.dsp.exec_cmd("{{screenshot_region}}"),
    { description = "Kibby foundation: region screenshot" })
replaceBind("SUPER + Print", hl.dsp.exec_cmd("{{screenshot_monitor}}"),
    { description = "Kibby foundation: active-monitor screenshot" })
