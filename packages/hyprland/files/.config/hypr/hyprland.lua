-- Kibby's Hyprland entry.
--
-- config/ is CachyOS's Hyprland template (cachyos-hypr-noctalia). Kibby's
-- installer fetches it at a pinned commit; it is not part of Kibby.
-- kibby/ is Kibby's own: settings, overrides and the Caelestia bridge.
-- kibby/init.lua is written by the installer and loads every installed
-- Kibby package's Hyprland module.

require("config.animations")
require("config.colors")
require("config.decorations")
require("config.variables")
-- After variables.lua and before binds.lua, so BROWSER and MONITOR1 come
-- from ~/.config/kibby/settings.env when the binds are made.
require("kibby.settings")
require("config.environment")
require("config.inputs")
require("config.binds")
require("config.misc")
require("config.windowrules")
require("config.workspaces")

-- Kibby replaces CachyOS's monitors.lua (it reads settings) and
-- autostart.lua (it would start the Noctalia shell; Kibby runs Caelestia).
require("kibby.monitors")
require("kibby.autostart")
require("kibby.init")
