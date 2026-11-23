-- Wispr Flow with Kibby's edge glow in place of Wispr's own bottom bar.

-- Wispr Flow's bottom bar stays out of sight; the edge glow
-- (~/.config/quickshell/wispr-glow) shows dictation instead. The launcher
-- already hides the bar; if Wispr ever maps it anyway, it lands on a special
-- workspace nobody opens, without focus or a frame. (Kibby's
-- wispr-status-hidden design, 2026-08-24.)
hl.window_rule({
    match = { class = "^(wispr-flow)$", title = "^(Status|Flow Status Indicator)$" },
    workspace = "special:wispr-status silent",
    float = true,
    no_focus = true,
    no_initial_focus = true,
    no_follow_mouse = true,
    no_shortcuts_inhibit = true,
    border_size = 0,
    no_shadow = true,
    no_blur = true,
    no_anim = true,
    no_dim = true,
})

hl.on("hyprland.start", function()
    hl.exec_cmd("{{HOME}}/.local/bin/wispr-flow --background")
    -- Wispr's edge glow (its bottom bar stays hidden); -n keeps one copy.
    hl.exec_cmd("qs -n -d -p {{HOME}}/.config/quickshell/wispr-glow")
end)
