# Kibby agent entrypoint

Kibby is Jagrit's desktop dots, packaged: Hyprland plus the Caelestia shell, with his own additions. Read `README.md` for the layout and the manifest fields.

- Never run `./install` against a real home. Test with a throwaway one, for example `HOME=$(mktemp -d) ./install`, and read the result.
- Never vendor upstream code that can be fetched instead. Changes to the Caelestia shell go to the fork, `JagritGumber/caelestia-shell` (branch `kibby`, one commit per change, listed in its `KIBBY.md`). Then pin the new commit in `packages/caelestia-shell/package.json`. To move to a new upstream release, rebase `kibby` onto the release tag, account for every conflict, and load the shell on a headless output before pinning.
- CachyOS's Hyprland template states no licence. Fetch it at install time and never copy its text into Kibby. Express changes to it as Kibby Lua that loads after it.
- Machine- or person-specific values become settings: add a `KIBBY_*` default to `settings.default.env`, then use `{{KIBBY_*}}` in files or read the settings file in scripts. Use `{{HOME}}` or `$HOME`, never a literal home path.
- Leave out personal apps, credentials, emails and private hostnames. Before each commit, scan for secrets (gitleaks if installed, otherwise grep) and never write a secret's value into notes.
- The installer writes only below `$HOME`. System files, builds and `systemctl` are printed for the user to run. A `postInstall` command follows the same rules and prints `next: ` lines for whatever it could not finish.
- To test a `postInstall` command, run the installer with a throwaway HOME and XDG dirs, inside `dbus-run-session` and with no display. Otherwise gsettings and KDE tools reach the real session.
- Keep each package one folder, `packages/<id>/`, with `package.json` at schemaVersion 2.
