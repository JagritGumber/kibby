# Kibby

Kibby is Jagrit's Linux desktop: Hyprland and the [Caelestia](https://github.com/caelestia-dots/shell) Quickshell shell, with his own pieces spliced in, as packages that anyone can install.

It runs on Arch Linux and CachyOS, with Hyprland 0.57 or newer (the Lua config).

## Packages

| Package | What it does |
| --- | --- |
| `hyprland` | Hyprland in Lua. The base is CachyOS's Hyprland template, fetched at a pinned commit. On top of it: number keys go to workspaces, a scratchpad toggle, the monitor rule from settings, the touchpad key, an empty wallpaper workspace, and the Caelestia bridge (launcher, sidebar, lock, OSD keys, OCR and translate, the colour picker). |
| `caelestia-shell` | Caelestia from Kibby's fork, [JagritGumber/caelestia-shell](https://github.com/JagritGumber/caelestia-shell): upstream v2.5.0 plus touchpad-lock and mic-mute feedback, each window's own app icon in the bar, tray fixes, system alerts, the profile picture cropper, per-app volume in the OSD on demand (rest the pointer on the volume pill, or on the mic pill while an app records, or right-click either; output and input switching), the notification dock for Junco's work items (see [Notification dock](#notification-dock) below), and notification, lock, launcher and recorder changes. |
| `caelestia-config` | Caelestia's `shell.json` and `cli.json`, and the Dolphin stylesheet template. |
| `theme-sync` | Runs once at install and after every wallpaper change. It sets Dolphin's Material style and the caelestia-folders icons, and recolours KDE/Qt apps, GTK apps and the Papirus folders from the wallpaper's palette. |
| `material-dolphin` | A Qt style plugin over Darkly. It gives Dolphin and the KDE file dialog Caelestia's Material look. Built from source. |
| `tray-standin` | A kded module, so the system tray works without Plasma. Built from source. |
| `wispr-glow` | While you dictate with Wispr Flow, the screen edges glow in the wallpaper's colours and ripple with your voice, and bars along the bottom edge move with each word. Errors turn the glow red. Wispr's own bar stays hidden. See [Wispr glow](#wispr-glow) below. |
| `desktop-scripts` | The helpers the binds call: mic mute, touchpad state, screen OCR, the recorder, the sleep hook, and clipboard history. |
| `mic-mute-led` | Keeps a laptop's mic-mute LED in step with PipeWire. |
| `appimage-icons` | Shows each AppImage's real icon in Dolphin. |
| `appimage-apps` | Lists the AppImages in `~/Applications` in the launcher. It writes an entry for each, with its own icon, without ever running it; repairs the entries some AppImages register from their temporary mount; and removes them when the AppImage goes. |
| `helium` | Workarounds for the Helium browser around sleep. |
| `terminal` | kitty, Alacritty, fish, fuzzel, Helix and micro settings. |
| `session` | The uwsm environment and the portal choices. |
| `keyd` | One Caps Lock across all keyboards, and mouse side buttons that switch workspaces. These are system files: Kibby prints the `sudo` commands. |

`./install --list` shows the packages with their versions.

**Junco, the mail app.** [Junco](https://github.com/JagritGumber/junco) is a mail client for Linux that feels like part of your desktop. It lives in its own repository, with its own install steps.

## Install

```sh
git clone https://github.com/JagritGumber/kibby ~/kibby && cd ~/kibby
./install --deps                 # the pacman and AUR packages to install first
cp settings.default.env ~/my-kibby.env && $EDITOR ~/my-kibby.env
./install --settings ~/my-kibby.env --dry-run
./install --settings ~/my-kibby.env
```

Then follow the "Next steps" the installer prints:
- reload systemd
- run the `sudo` commands for keyd
- build the two plugins
- pick a wallpaper, which colours everything

Log out and back in to start the session.

- Everything is written below `$HOME`.
- Each file the install would replace is first copied to `~/.local/state/kibby/backups/<time>/`.
- The installer never uses `sudo` and never runs `systemctl`.
- To install only some packages, name them: `./install wispr-glow`. Their dependencies come along.

## Dolphin's look

Dolphin gets two things from Kibby:

- **Caelestia's Material look.** The `material-dolphin` package is a Qt style plugin that redraws Dolphin and the KDE file dialog in the Caelestia shell's Material shapes, on top of Darkly. You build it yourself: run the three `cmake` lines from the installer's next steps. Until it is built, Dolphin keeps its default look.
- **The caelestia-folders icons.** This is Papirus with its folder icons recoloured to match your wallpaper, plus a few plain icons for the Places panel. It needs Papirus (`papirus-icon-theme`, listed by `./install --deps`).

**At install:** `./install` runs `caelestia-sync-kde-theme` once. It sets Dolphin's style to `caelestia` and its icon theme to `caelestia-folders`, for Qt and GTK apps too. It also builds caelestia-folders, but with Papirus's own blue folders, because Caelestia has no wallpaper colours yet. Dolphin picks this up the next time it starts in a Kibby session. The session is what lets Qt find the style, in `~/.local/lib/qt6/plugins`.

**At every wallpaper change:** Caelestia runs the same script after it makes the new colours. The script recolours KDE and GTK apps and the folder icons, and running apps reload them. So the folders stay Papirus blue only until you first pick a wallpaper; the installer's next steps say so.

## Wispr glow

The glow is drawn on the GPU: the edge gradients and the voice ribbons are shaders, and so are the bottom bars.

- **The bars' look.** `wispr-glow-style` switches it live, with nothing restarted:
  - `kurve` (the default) is rounded bars in the colours of the Kurve Plasma widget.
  - `rainbow` uses Kurve's full-hue colours.
  - `wallpaper` uses the wallpaper's own colours.
  - `caelestia` looks like Caelestia's desktop visualiser.

  `wispr-glow-style` with no argument prints the current look. Until the first switch, the look is `KIBBY_WISPR_BAR_STYLE`. The switch is saved in `$XDG_STATE_HOME/wispr-glow/bar-style`, a folder the installer creates.
- **The bars themselves.** `KIBBY_WISPR_BARS` turns them on or off. `KIBBY_WISPR_BAR_COUNT` sets how many go across the screen (0 means the look's own count), and `KIBBY_WISPR_BAR_MAX_HEIGHT` sets their height at full voice.
- **The voice.** `KIBBY_WISPR_INPUT_GAIN=0` sets the gain automatically from your mic. If soft words barely move the glow, lower `KIBBY_WISPR_GATE_DB` from 14 (10 suits a quiet headset); if it moves while you are silent, raise it.
- **The shaders.** At install, Kibby builds each shader with your system's `qsb` (from `qt6-shadertools`), so they match your Qt. Without `qsb`, it uses the packs shipped in `packages/wispr-glow/prebuilt`, built with Qt 6.12.0. Those may not load on an older Qt, and the installer's next steps say so.

## Notification dock

The Caelestia shell from Kibby's fork has a dock for the work Junco, the mail app, finds in your mail: a CI run to re-run, a sign-in to confirm, a review, a comment to answer, an invitation, a bill. Normal notifications still come as Caelestia's popups.

- **Where it is.** While there is work, a thin line in the wallpaper's accent colour shows in the bottom border, in the bottom-left corner beside the bar. Rest the pointer on the edge under it (50 ms) and the sheet comes up; move away and it goes, as the dashboard does. You can also bind the global shortcut `caelestia:notifDock`, or run `qs -c caelestia ipc call drawers toggle notifDock`.
- **What it shows.** A Material 3 list-detail sheet: a tab per source with its count, search, and a filter for what needs you (Actions) or is only news (Updates); the list; and one item's detail, with its own buttons pinned at the bottom and the rest scrolling. **Later** sends an item to the back of the list; **Mark read** marks its mail read in Junco and lets it go. After a click on the sheet, ↑ and ↓ move through the list, ← is Later, and → or R is Mark read.
- **How Junco feeds it.** Junco writes its items to `${XDG_STATE_HOME:-~/.local/state}/courier/dock.json` (version 3, written atomically), and the dock only reads that file. Each item names one component from a fixed set (decision, status, review, comment, scheduling, table, timeline, summary) and fills that component's sections; the dock draws it in the wallpaper's colours. Buttons run `courier-notify action <id> <action-id>` (a reply's text on stdin); links open only through `xdg-open`, and only http(s). While the dock runs it rewrites `${XDG_STATE_HOME}/caelestia/notifdock.alive` every 30 s; when that is older than 90 s, Junco falls back to desktop notifications. Without Junco, the dock stays hidden.
- **Settings**, under `"notifs"` in `~/.config/caelestia/shell.json`:
  - `"dock": false` turns it off.
  - `"dockRevealDelay"`: how long the pointer rests on the edge first, in ms (50).
  - `"dockScale"`: its size, from 0.6 to 1.6; 1 is 990 × 480 px.
  - `"dockLayout": "deck"` shows one card at a time instead of the sheet.

  Caelestia's plugin doesn't know these keys, so any you set are listed among its config issues; they still apply.

## Settings

`~/.config/kibby/settings.env` holds everything that differs per machine or person:
- browser
- monitor and scale
- numlock
- touchpad device
- mic-mute LED
- the Wispr glow: mic gain and gate, and the bottom bars
- keyd device IDs

`settings.default.env` documents each setting. `examples/vivobook-15.env` holds the values of the machine Kibby was made on.

Package files use `{{HOME}}` and `{{KIBBY_*}}` placeholders, which the installer fills in. Scripts and units also read the settings file directly. To change a setting, edit the file and run `./install` again.

## Upstream code

Kibby copies no upstream wholesale:

- **Caelestia shell** (GPL-3.0). Kibby's changes live in a fork, [JagritGumber/caelestia-shell](https://github.com/JagritGumber/caelestia-shell). Its `kibby` branch is upstream `v2.5.0` with one commit per change, and `KIBBY.md` there lists them. The installer checks out the fork at a pinned commit into `~/.config/quickshell/caelestia`.
- **CachyOS Hyprland template** (`cachyos-hypr-noctalia`). It states no licence, so Kibby does not include it. The installer fetches it from CachyOS at a pinned commit into `~/.config/hypr/config/`. Kibby's own Lua in `~/.config/hypr/kibby/` loads after it.
- The shell's compiled plugin, `caelestia-cli`, Quickshell and Darkly come from the AUR. `./install --deps` lists the versions this setup was made with: `caelestia-shell` 2.5.0 and `caelestia-cli` 1.1.2.

## Layout

```text
install                    the installer (Python 3, standard library only)
settings.default.env       every setting, with defaults
examples/                  settings for real machines
packages/<id>/package.json the manifest (schemaVersion 2, below)
packages/<id>/files/       files that land in $HOME, at the same relative paths
packages/<id>/system/      files for / (rendered, then copied with sudo)
packages/<id>/prebuilt/    fallbacks used when a build tool is missing (wispr-glow's shader packs)
```

`package.json` keeps the old Kibby manifest (`id`, `name`, `version`, `kind`, `license`, `dependencies`, `settings`) and adds these fields:

| Field | What it lists |
| --- | --- |
| `upstream` | Code fetched at a pinned commit, as files or as a whole checkout |
| `hyprland` | Lua modules that `kibby/init.lua` loads |
| `services` | User units to enable |
| `systemFiles` | Files for `/` |
| `build` | Build commands |
| `notes` | Instructions printed after install |
| `postInstall` | Commands run once everything is in place. A command whose tools are missing becomes a next step, and so do lines it prints that start with `next: ` |
| `seed` | Files a program rewrites itself (Caelestia, on every colour change): written only when they do not exist yet |
| `choices` | Allowed values for a setting; anything else is refused before install |
| `stateDirs` | Folders created under `$XDG_STATE_HOME` |
| `shaders` | Shader sources built into `.qsb` packs with the system `qsb`, or else taken from the package's prebuilt packs |
| `system` | pacman and AUR packages, and version pins |

## History

- Kibby began in August 2026 as a Rust tool in this repository that copied optional Hyprland components into place (the first commit, dc0eaac). The old runtime packages (`wispr-glow` 0.1.3 and its parts) came from it.
- In November 2026 the desktop it grew into became the dots themselves: the packages above and a small installer.

## Credits

See [NOTICE.md](NOTICE.md). Kibby is GPL-3.0, the same as Caelestia.
