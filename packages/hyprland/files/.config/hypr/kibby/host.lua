-- Host helpers that sit beside the Caelestia shell: the Qt environment for
-- apps the shell launches, the touchpad toggle, an empty wallpaper workspace,
-- and a few app-specific fixes.

-- Native Qt/KDE applications launched by Caelestia inherit Hyprland's
-- environment, so publish the KDE platform theme before startup callbacks run.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
-- The caelestia Qt style (kdeglobals widgetStyle) is a user plugin; apps the
-- shell launches must find it, or Dolphin falls back to Breeze.
hl.env("QT_PLUGIN_PATH", "{{HOME}}/.local/lib/qt6/plugins")

-- Zoom 7.1.5 exposes its 112x112 annotation control as a separate XWayland
-- window. Keep only that helper floating so Hyprland does not tile it into a
-- half-screen surface; Zoom retains its own size, position, and input handling.
hl.window_rule({
    name = "kibby-zoom-annotation-toolbar",
    match = {
        class = "^(zoom)$",
        initial_title = "^(annotate_toolbar)$",
    },
    float = true,
})

-- Caelestia's profile picture cropper is a small dialog: float it, centred.
hl.window_rule({
    match = { class = "^(org\\.quickshell)$", title = "^(Crop profile picture)$" },
    float = true,
    center = true,
})

-- Dolphin opens at two thirds of the screen, 1280x760 on 1920x1080.
-- CachyOS's windowrules.lua floats Dolphin, sizes it and places it under the
-- cursor. This rule loads after it and replaces only the size; Hyprland sizes
-- a window before it places it, so the placement uses this size. Dolphin's
-- dialogs (copy progress, properties and the like) keep their own size.
local dolphinDialogs = {
    "Moving", "Create New", "Extract", "Compress", "Copying", "Progress",
    "Configure", "Properties", "Choose Application",
}
hl.window_rule({
    name = "kibby-dolphin-size",
    match = {
        class = "^(org\\.kde\\.dolphin)$",
        title = "negative:^(" .. table.concat(dolphinDialogs, "|") .. ").*$",
    },
    size = { "monitor_w*0.667", "monitor_h*0.704" },
})

KIBBY = KIBBY or {}
KIBBY.touchpadEnabled = KIBBY.touchpadEnabled ~= false
KIBBY.wallpaperWorkspaceName = "kibby-wallpaper"
KIBBY.wallpaperWorkspaceSelector = "name:" .. KIBBY.wallpaperWorkspaceName

-- The laptop's hardware touchpad key (KIBBY_TOUCHPAD_DEVICE, the name from
-- `hyprctl devices`). Left empty, the key keeps Hyprland's default.
if KIBBY.settings.touchpadDevice ~= "" then
    function KIBBY.toggleTouchpad()
        KIBBY.touchpadEnabled = not KIBBY.touchpadEnabled
        hl.device({
            name = KIBBY.settings.touchpadDevice,
            enabled = KIBBY.touchpadEnabled,
        })
        hl.exec_cmd("{{HOME}}/.local/bin/kibby-touchpad-state " ..
            (KIBBY.touchpadEnabled and "enabled" or "disabled"))
    end

    hl.unbind("XF86TouchpadToggle")
    hl.bind("XF86TouchpadToggle", KIBBY.toggleTouchpad,
        { description = "Touchpad: toggle the built-in touchpad" })

    hl.on("hyprland.start", function()
        hl.exec_cmd("{{HOME}}/.local/bin/kibby-touchpad-state enabled --quiet")
    end)
end

function KIBBY.toggleWallpaperWorkspace()
    local workspace = hl.get_active_workspace()
    if not workspace then
        return
    end

    if workspace.name == KIBBY.wallpaperWorkspaceName then
        local return_workspace = KIBBY.wallpaperReturnWorkspace or "1"
        KIBBY.wallpaperReturnWorkspace = nil
        hl.dispatch(hl.dsp.focus({ workspace = return_workspace }))
        return
    end

    KIBBY.wallpaperReturnWorkspace = tostring(workspace.id)
    hl.dispatch(hl.dsp.focus({ workspace = KIBBY.wallpaperWorkspaceSelector }))
end

hl.bind("SUPER + G", KIBBY.toggleWallpaperWorkspace,
    { description = "Wallpaper: toggle empty workspace" })
hl.bind("SUPER + SHIFT + Escape",
    hl.dsp.exec_cmd("uwsm app -- plasma-systemmonitor"),
    { description = "System monitor: open Plasma System Monitor" })
