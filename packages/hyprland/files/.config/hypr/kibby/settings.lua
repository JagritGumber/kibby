-- Written by Kibby's installer from ~/.config/kibby/settings.env.
-- Change that file and run ./install again rather than editing this one.

KIBBY = KIBBY or {}
KIBBY.settings = {
    browser = "{{KIBBY_BROWSER}}",
    monitor = "{{KIBBY_MONITOR}}",
    monitorScale = "{{KIBBY_MONITOR_SCALE}}",
    numlockByDefault = {{KIBBY_NUMLOCK_BY_DEFAULT}},
    touchpadDevice = "{{KIBBY_TOUCHPAD_DEVICE}}",
}

BROWSER = KIBBY.settings.browser
MONITOR1 = KIBBY.settings.monitor
PRIMARY_MONITOR = MONITOR1
