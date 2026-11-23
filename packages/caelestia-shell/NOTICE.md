# Caelestia shell, Kibby fork

This package installs [JagritGumber/caelestia-shell](https://github.com/JagritGumber/caelestia-shell). That repository is a fork of the Caelestia shell by the caelestia-dots contributors (<https://github.com/caelestia-dots/shell>), licensed under GPL-3.0. Kibby includes none of its code: the installer checks out the fork at the commit pinned in `package.json`.

**Fork branch `kibby`:** upstream tag v2.5.0 (d999d487) plus Jagrit Gumber's changes, one commit per change. `KIBBY.md` in the fork lists them.

**Versions:** the compiled `Caelestia` QML plugin comes from the AUR `caelestia-shell` package. This fork is meant for plugin 2.5.0, the same release as its base; `./install` says so when another version is installed.
