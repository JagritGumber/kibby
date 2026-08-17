#!/usr/bin/env bash
set -euo pipefail

geometry=$(slurp)
grim -g "$geometry" - | wl-copy --type image/png
