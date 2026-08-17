#!/usr/bin/env bash
set -euo pipefail

monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n 1)
if [[ -z "$monitor" ]]; then
    echo "Kibby could not determine the focused monitor" >&2
    exit 1
fi
grim -o "$monitor" - | wl-copy --type image/png
