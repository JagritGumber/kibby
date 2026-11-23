-- One monitor rule from settings (KIBBY_MONITOR, KIBBY_MONITOR_SCALE).
-- An empty KIBBY_MONITOR matches every output. See
-- https://wiki.hypr.land/Configuring/Basics/Monitors/ and `hyprctl monitors`.

hl.monitor({
    output    = KIBBY.settings.monitor,
    mode      = "preferred",
    position  = "auto",
    scale     = KIBBY.settings.monitorScale,
})
