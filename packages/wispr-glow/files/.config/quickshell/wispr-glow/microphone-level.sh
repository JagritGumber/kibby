#!/usr/bin/env bash
set -euo pipefail

readonly template="${1:?missing Cava template path}"
readonly runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
readonly runtime_config="${runtime_dir}/kibby-wispr-cava-${UID}.conf"
source_name="$(pactl get-default-source)"
[[ "${source_name}" =~ ^[A-Za-z0-9_.:-]+$ ]] || exit 2
sed "s|@SOURCE@|${source_name}|g" "${template}" > "${runtime_config}"
exec cava -p "${runtime_config}"
