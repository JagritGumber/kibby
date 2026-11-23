-- Session start. The Caelestia shell itself starts from kibby/caelestia.lua;
-- other packages add their own starts in their modules.

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)
