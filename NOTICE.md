# Notices

Kibby is licensed under the GNU General Public License, version 3 (see `LICENSE`).

## Kibby's own earlier work

- `wispr-glow` grew out of Kibby's first packages (`edge-aura`, `wispr-flow` and `wispr-status-hidden`, GPL-3.0-or-later).

## Fetched at install time, not included

- **Caelestia shell**, by the caelestia-dots contributors: <https://github.com/caelestia-dots/shell>, GPL-3.0.
  - Kibby's changes to it live in the fork [JagritGumber/caelestia-shell](https://github.com/JagritGumber/caelestia-shell), branch `kibby`: upstream v2.5.0 plus one commit per change, made by Jagrit Gumber from September to November 2026.
  - The fork keeps upstream's licence and history; `KIBBY.md` there lists the changes.
  - The installer checks out the fork at the commit pinned in `packages/caelestia-shell/package.json`.

- **CachyOS Hyprland template**, `CachyOS/cachyos-hypr-noctalia`: <https://github.com/CachyOS/cachyos-hypr-noctalia>.
  - The repository states no licence, so Kibby does not include any of its files.
  - The installer fetches them from CachyOS at commit baabb428.
  - Kibby's Hyprland files load after them and contain none of their text.

## Used, not included

- [Quickshell](https://quickshell.org), [caelestia-cli](https://github.com/caelestia-dots/cli) and the Caelestia shell plugin, installed from the AUR.
- [Darkly](https://github.com/Bali10050/Darkly). Material Dolphin draws over it at run time.
- [Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme). The theme sync recolours a copy of its folder icons on your machine.
- Wispr Flow and its Arch and Hyprland port, `wispr-flow-hyprland` (AUR).
- [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4 inspired the first Kibby.
