# Foundation contract

`kibby init` automatically installs foundation. Its purpose is to keep an
existing Hyprland desktop operable even when every optional shell process is
stopped or removed.

Foundation provides direct bindings for Kitty, Fuzzel, Hyprlock, WirePlumber
volume control, brightnessctl, and Grim/Slurp screenshots. It produces no bar,
OSD, notification center, wallpaper, sidebar, or settings UI.

For ordinary Hyprland, Kibby appends one marked `source` line to `hyprland.conf`.
For CachyOS Lua, it appends one marked `require("kibby.foundation")` line to
`hyprland.lua`. The included layer loads last and reversibly unbinds/rebinds only
foundation shortcuts. Removing the marked include restores the host behavior.

Defaults are deliberately replaceable through `~/.config/kibby/kibby.json`.
Package names are adapter data, not component source assumptions.
