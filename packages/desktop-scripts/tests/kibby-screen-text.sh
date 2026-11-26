#!/usr/bin/env bash
# Runs kibby-screen-text against stand-ins for grim, slurp, tesseract, trans,
# fuzzel, wl-copy and notify-send, in a throwaway HOME with a PATH of its own,
# so no region is picked, nothing is read off the screen and the clipboard is
# left alone.
#   packages/desktop-scripts/tests/kibby-screen-text.sh [SCRIPT]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$(readlink -f "${1:-$here/../files/.local/bin/kibby-screen-text}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bin="$work/bin" log="$work/log"
mkdir -p "$bin" "$log"

# The tools the script needs that are not under test.
for tool in bash cat dirname grep mkdir mktemp printf rm sed tail tee; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
done
stub() {  # stub NAME BODY: a stand-in that logs its arguments to $log/NAME
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/%s"\n%s\n' "$log" "$1" "$2" >"$bin/$1"
    chmod +x "$bin/$1"
}
stub slurp 'if [[ -n "${SLURP_FAIL:-}" ]]; then exit 1; fi; echo "10,10 100x50"'
stub grim 'printf png > "${!#}"'
stub tesseract 'printf "%s\n" "${OCR_TEXT:-Bonjour le monde}"'
stub trans 'while [[ $1 != -t ]]; do shift; done; t=$2; shift 2; [[ $1 == -- ]] || exit 3; shift; printf "[%s] %s\n" "$t" "$1"'
stub fuzzel 'cat > "'"$log"'/fuzzel-input"; printf "%s\n" "${FUZZEL_CHOICE:-}"; exit "${FUZZEL_EXIT:-0}"'
stub wl-copy 'cat > "'"$log"'/clipboard"'
stub notify-send ':'

failures=0
run() {  # run EXPECTED_STATUS ARGS...: run the script in a fresh log
    local expected="$1"
    shift
    rm -f "$log"/*
    set +e
    env -i HOME="$work/home" PATH="$bin" XDG_RUNTIME_DIR="$work" \
        ${KIBBY_TRANSLATE_TO+KIBBY_TRANSLATE_TO="$KIBBY_TRANSLATE_TO"} \
        ${OCR_TEXT+OCR_TEXT="$OCR_TEXT"} ${SLURP_FAIL+SLURP_FAIL=1} \
        ${FUZZEL_CHOICE+FUZZEL_CHOICE="$FUZZEL_CHOICE"} ${FUZZEL_EXIT+FUZZEL_EXIT="$FUZZEL_EXIT"} \
        "$script" "$@" >"$work/stdout" 2>"$work/stderr"
    status=$?
    set -e
    if [[ $status != "$expected" ]]; then
        fail "exit $status, expected $expected ($*): $(cat "$work/stderr")"
    fi
}
fail() {
    printf 'FAIL %s: %s\n' "$label" "$1"
    failures=$((failures + 1))
}
expect_file() {  # expect_file FILE CONTENT
    local got
    got="$(cat "$log/$1" 2>/dev/null)" || got="<missing>"
    [[ "$got" == "$2" ]] || fail "$1 is '$got', expected '$2'"
}
expect_absent() {
    [[ ! -e "$log/$1" ]] || fail "$1 ran: $(cat "$log/$1")"
}
settings() {
    mkdir -p "$work/home/.config/kibby"
    printf '%s\n' "$@" >"$work/home/.config/kibby/settings.env"
}
state="$work/home/.local/state/kibby/screen-text-language"
reset_home() {
    rm -rf "$work/home"
    mkdir -p "$work/home"
}

label="no argument is ocr"; reset_home
run 0
expect_file clipboard "Bonjour le monde"
expect_absent trans
expect_absent fuzzel

label="translate with no settings file uses en, no picker"; reset_home
run 0 translate
expect_file clipboard "[en] Bonjour le monde"
expect_absent fuzzel

label="translate uses KIBBY_TRANSLATE_TO from settings.env"; reset_home
settings 'KIBBY_BROWSER=firefox' 'KIBBY_TRANSLATE_TO=hi'
run 0 translate
expect_file clipboard "[hi] Bonjour le monde"
expect_absent fuzzel

label="the last line wins, comments and quotes are handled"; reset_home
settings 'KIBBY_TRANSLATE_TO=hi' '# KIBBY_TRANSLATE_TO=de' '  KIBBY_TRANSLATE_TO = "zh-CN"  ' 'KIBBY_TRANSLATE_TO_OLD=fr'
run 0 translate
expect_file clipboard "[zh-CN] Bonjour le monde"

label="an empty setting means en"; reset_home
settings 'KIBBY_TRANSLATE_TO='
run 0 translate
expect_file clipboard "[en] Bonjour le monde"

label="the environment overrides the settings file"; reset_home
settings 'KIBBY_TRANSLATE_TO=hi'
KIBBY_TRANSLATE_TO=fr run 0 translate
expect_file clipboard "[fr] Bonjour le monde"

label="a bad setting stops before the region is picked"; reset_home
settings 'KIBBY_TRANSLATE_TO=english please'
run 1 translate
expect_absent slurp
expect_absent clipboard
grep -q 'KIBBY_TRANSLATE_TO is not a language code' "$log/notify-send" 2>/dev/null || fail "no notification"

label="--ask opens the picker on the default"; reset_home
settings 'KIBBY_TRANSLATE_TO=ja'
FUZZEL_CHOICE='hi  Hindi' run 0 translate --ask
[[ "$(head -n 1 "$log/fuzzel-input")" == 'ja  Japanese' ]] || fail "picker starts on '$(head -n 1 "$log/fuzzel-input")'"
[[ "$(grep -c . "$log/fuzzel-input")" == 8 ]] || fail "picker has $(grep -c . "$log/fuzzel-input") lines"
expect_file clipboard "[hi] Bonjour le monde"
[[ "$(cat "$state" 2>/dev/null)" == hi ]] || fail "remembered '$(cat "$state" 2>/dev/null)'"

label="--ask starts on the last pick, Super+B keeps the default"; # same home
FUZZEL_CHOICE='es  Spanish' run 0 translate --ask
[[ "$(head -n 1 "$log/fuzzel-input")" == 'hi  Hindi' ]] || fail "picker starts on '$(head -n 1 "$log/fuzzel-input")'"
grep -qx 'ja  Japanese' "$log/fuzzel-input" || fail "Japanese left the list"
run 0 translate
expect_file clipboard "[ja] Bonjour le monde"
expect_absent fuzzel

label="--ask takes a typed code and remembers it"; reset_home
FUZZEL_CHOICE='pt-BR' run 0 translate --ask
expect_file clipboard "[pt-BR] Bonjour le monde"
FUZZEL_CHOICE='en  English' run 0 translate --ask
[[ "$(head -n 1 "$log/fuzzel-input")" == 'pt-BR' ]] || fail "picker starts on '$(head -n 1 "$log/fuzzel-input")'"
[[ "$(grep -c . "$log/fuzzel-input")" == 9 ]] || fail "picker has $(grep -c . "$log/fuzzel-input") lines"

label="--ask refuses a typed word that is not a code"; reset_home
FUZZEL_CHOICE='hello world' run 1 translate --ask
expect_absent trans
expect_absent clipboard
[[ ! -e "$state" ]] || fail "remembered '$(cat "$state")'"

label="Escape in the picker copies nothing"; reset_home
FUZZEL_EXIT=1 run 0 translate --ask
expect_absent trans
expect_absent clipboard

label="--ask without fuzzel uses the default"; reset_home
settings 'KIBBY_TRANSLATE_TO=de'
mv "$bin/fuzzel" "$work/fuzzel.off"
run 0 translate --ask
mv "$work/fuzzel.off" "$bin/fuzzel"
expect_file clipboard "[de] Bonjour le monde"

label="OCR text starting with - stays text"; reset_home
OCR_TEXT='-v is not an option' run 0 translate
expect_file clipboard "[en] -v is not an option"

label="a cancelled region copies nothing"; reset_home
SLURP_FAIL=1 run 0 translate
expect_absent grim
expect_absent clipboard

label="translate without trans stops before the region is picked"; reset_home
mv "$bin/trans" "$work/trans.off"
run 1 translate
mv "$work/trans.off" "$bin/trans"
expect_absent slurp

for args in "translate --bogus" "translate --ask extra" "ocr --ask" "ocr extra" "translate-ask" "--ask"; do
    label="bad arguments: $args"; reset_home
    # shellcheck disable=SC2086
    run 2 $args
    expect_absent slurp
    grep -q '^Usage:' "$work/stderr" || fail "no usage message"
done

if (( failures )); then
    echo "$failures failed"
    exit 1
fi
echo "kibby-screen-text: all cases pass"
