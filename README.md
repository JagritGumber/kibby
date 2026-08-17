# Kibby

Kibby is a source-owning component system for existing Hyprland desktops. It
layers a small recovery foundation onto the user's current configuration, then
copies optional component source into the XDG paths where it actually runs.

Kibby is not a distribution, a replacement Hyprland configuration, or a shell
theme bundle. It is closer to shadcn: inspect the plan, add only what you want,
and keep the resulting source.

Kibby was directly inspired by end-4's
[illogical-impulse](https://github.com/end-4/dots-hyprland). It takes selected
foundational design and implementation references from that project while
reworking the experience around independently installable, user-owned modules.
Kibby is an independent project and is not an official illogical-impulse
distribution.

## Foundation workflow

```bash
kibby init --dry-run
kibby init
kibby doctor
```

`kibby init` installs a Quickshell-independent recovery layer with direct
terminal, launcher, lock, audio, brightness, and screenshot bindings. Existing
monitor, workspace, animation, input, window-rule, and theme configuration stays
owned by the host desktop.

Arch Linux and CachyOS are the first tested package adapters. Missing official
packages are previewed and require confirmation. Kibby never removes packages,
builds AUR packages, or replaces theme packages.

See `docs/architecture.md` and `docs/foundation.md` for the safety model.
