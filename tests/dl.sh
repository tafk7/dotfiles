#!/bin/bash
# bin/dl: lookup (here, then DL_PATH), staging into a private ~/.cache/dl with
# names the WezTerm side accepts, the dl_fetch user variable (plain and wrapped
# for tmux), pruning, the --print / --wezterm-config forms WezTerm uses,
# --wezterm's dl_config, bin/up's side of an upload (WezTerm's part played by
# writing into the slot), and shell/tools/dl.sh's bash completion.
# configs/wezterm.lua's side is exercised by hand on Windows (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
fail() { echo "FAIL: line ${BASH_LINENO[0]}: $*" >&2; exit 1; }

export HOME="$TEST_ROOT/home"
mkdir -p "$HOME" "$TEST_ROOT/work" "$TEST_ROOT/lib/configs"
cd "$TEST_ROOT/work"
dl="$ROOT/bin/dl"
unset TMUX DL_PATH
# No controlling terminal, so the user variable goes to stdout where we can read it.
run() { setsid -w "$dl" "$@" 2>"$TEST_ROOT/err"; }
uservar() {   # decode the user variable ${2:-dl_fetch}'s value(s) in "$1"
    local var="${2:-dl_fetch}"
    grep -o "SetUserVar=$var=[A-Za-z0-9+/=]*" <<< "$1" | while IFS= read -r v; do
        printf '%s\n' "${v#SetUserVar="$var"=}" | base64 -d; echo
    done
}

# --- A file here: staged privately, announced, and the scp fallback printed.
printf 'hello\n' > 'my report.txt'
out="$(run 'my report.txt')"
staged="$(uservar "$out")"
[[ "$staged" =~ ^[A-Za-z0-9]{12}/my_report\.txt$ ]] || fail "staged name: $staged"
[[ "$(cat "$HOME/.cache/dl/$staged")" == hello ]] || fail "staged content"
[[ "$(stat -c %a "$HOME/.cache/dl/${staged%/*}")" == 700 ]] || fail "staging dir not private"
[[ "$(stat -c %a "$HOME/.cache/dl/$staged")" == 600 ]] || fail "staged file not private"
[[ "$out" == $'\e]1337;SetUserVar=dl_fetch='*$'\a' ]] || fail "plain sequence: $(printf %q "$out")"
grep -q "scp .*:.cache/dl/$staged \.$" "$TEST_ROOT/err" || fail "no scp fallback: $(cat "$TEST_ROOT/err")"

# --- Inside tmux the sequence is wrapped for passthrough, escapes doubled.
out="$(TMUX=/tmp/x,1,0 run 'my report.txt')"
[[ "$out" == $'\ePtmux;\e\e]1337;SetUserVar=dl_fetch='*$'\a\e\\' ]] || fail "tmux sequence: $(printf %q "$out")"

# --- Several files: one variable each.
printf a > a.txt; printf b > b.txt
[[ "$(uservar "$(run a.txt b.txt)" | sed 's|.*/||' | tr '\n' ' ')" == 'a.txt b.txt ' ]] || fail "two files"

# --- DL_PATH: a relative name not found here is looked up there, in order.
printf one > "$TEST_ROOT/lib/configs/x.lua"
mkdir -p "$TEST_ROOT/other/configs"; printf two > "$TEST_ROOT/other/configs/x.lua"
staged="$(DL_PATH="$TEST_ROOT/missing:$TEST_ROOT/lib:$TEST_ROOT/other" run --print configs/x.lua)"
[[ "$(cat "$HOME/.cache/dl/$staged")" == one ]] || fail "DL_PATH order"
mkdir -p configs; printf here > configs/x.lua
staged="$(DL_PATH="$TEST_ROOT/lib" run --print configs/x.lua)"
[[ "$(cat "$HOME/.cache/dl/$staged")" == here ]] || fail "the current directory comes first"
rm -r configs

# --- Refusals: missing, a directory, nothing staged.
before="$(find "$HOME/.cache/dl" -mindepth 1 -maxdepth 1 | wc -l)"
run nope.txt >/dev/null && fail "missing file accepted"
grep -q 'not found here' "$TEST_ROOT/err" || fail "missing message: $(cat "$TEST_ROOT/err")"
DL_PATH="$TEST_ROOT/lib" run nope.txt >/dev/null && fail "missing file accepted"
grep -q "or in DL_PATH" "$TEST_ROOT/err" || fail "DL_PATH not named"
run "$TEST_ROOT/lib" >/dev/null && fail "directory accepted"
[[ "$(find "$HOME/.cache/dl" -mindepth 1 -maxdepth 1 | wc -l)" == "$before" ]] || fail "a refusal staged something"
run >/dev/null 2>&1 && fail "no arguments: exit 0"
run --help | grep -q '^Usage: dl FILE' || fail "--help"

# --- Names: anything outside [A-Za-z0-9._-] becomes _, trailing dots go.
for pair in 'a b&c.txt=a_b_c.txt' 'résumé.pdf=r_sum_.pdf' 'dots...=dots' '.wezterm.lua=.wezterm.lua' '...=file'; do
    printf x > "${pair%%=*}"
    staged="$(run --print "${pair%%=*}")"
    [[ "${staged#*/}" == "${pair#*=}" ]] || fail "name ${pair%%=*} -> ${staged#*/}"
done

# --- --wezterm-config stages this checkout's file, and prints only its name.
staged="$(run --wezterm-config)"
[[ "$staged" =~ ^[A-Za-z0-9]{12}/wezterm\.lua$ ]] || fail "--wezterm-config: $staged"
cmp -s "$HOME/.cache/dl/$staged" "$ROOT/configs/wezterm.lua" || fail "--wezterm-config content"

# --- --wezterm sends it as dl_config (never dl_fetch), and takes no files.
out="$(run --wezterm)"
staged="$(uservar "$out" dl_config)"
[[ "$staged" =~ ^[A-Za-z0-9]{12}/wezterm\.lua$ ]] || fail "--wezterm: $(printf %q "$out")"
[[ -z "$(uservar "$out")" ]] || fail "--wezterm also set dl_fetch"
cmp -s "$HOME/.cache/dl/$staged" "$ROOT/configs/wezterm.lua" || fail "--wezterm content"
grep -q 'asks before replacing' "$TEST_ROOT/err" || fail "--wezterm message: $(cat "$TEST_ROOT/err")"
run --wezterm a.txt >/dev/null && fail "--wezterm with a file accepted"

# --- Completion: options after -, files here and through DL_PATH.
mkdir -p "$TEST_ROOT/lib/sub"
complete_dl() {   # print COMPREPLY for "dl $1", one per line
    DL_PATH="$TEST_ROOT/lib" bash --norc --noprofile -c '
        source "$1/shell/tools/dl.sh"
        COMP_WORDS=(dl "$2"); COMP_CWORD=1; _dl_complete
        printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT" "$1"
}
[[ "$(complete_dl --we | tr '\n' ' ')" == '--wezterm --wezterm-config ' ]] || fail "complete --we: $(complete_dl --we)"
complete_dl configs/ | grep -qx 'configs/x.lua' || fail "complete through DL_PATH: $(complete_dl configs/)"
complete_dl su | grep -qx 'sub/' || fail "a DL_PATH directory: $(complete_dl su)"
complete_dl a. | grep -qx 'a.txt' || fail "complete here: $(complete_dl a.)"
complete_up() {   # print COMPREPLY for "up $1 $2" (the cursor on the last word)
    bash --norc --noprofile -c '
        source "$1/shell/tools/dl.sh"
        COMP_WORDS=(up "${@:2}"); COMP_CWORD=$(( $# - 1 )); _up_complete
        printf "%s\n" "${COMPREPLY[@]}"' _ "$ROOT" "$@"
}
[[ -z "$(complete_up a.)" ]] || fail "up completed a Windows path: $(complete_up a.)"
complete_up 'C:\x' a. | grep -qx 'a.txt' || fail "up DEST: $(complete_up 'C:\x' a.)"

# --- up: asks WezTerm through up_request, then takes what lands in the slot.
up="$ROOT/bin/up"
# Start up in the background; set v to its up_request value once it is sent.
# (Not in $(...): the background up would hold that pipe open.)
up_start() {
    : > "$TEST_ROOT/up.out"
    ( cd "$TEST_ROOT/work" && exec setsid -w "$up" "$@" > "$TEST_ROOT/up.out" 2> "$TEST_ROOT/up.err" ) \
        </dev/null >/dev/null 2>&1 &
    up_pid=$!
    local i
    for i in $(seq 100); do
        grep -q $'\a' "$TEST_ROOT/up.out" 2>/dev/null && break
        sleep 0.05
    done
    v="$(uservar "$(cat "$TEST_ROOT/up.out")" up_request)"
    [[ -n "$v" ]] || { kill "$up_pid" 2>/dev/null; fail "up sent no up_request: $(cat "$TEST_ROOT/up.err")"; }
}
# Play WezTerm: put FILE (named NAME) in the slot, then STATUS.
up_answer() {   # value status [name content]
    local slot="$HOME/.cache/up/${1%%$'\n'*}"
    [[ -n "${3:-}" ]] && printf '%s' "$4" > "$slot/$3"
    printf '%s' "$2" > "$slot/.status"
    up_rc=0
    wait "$up_pid" || up_rc=$?
}
up_start 'C:\Users\me\report.pdf'
[[ "$(sed -n 2p <<< "$v")" == 'C:\Users\me\report.pdf' ]] || fail "up path: $(printf %q "$v")"
[[ "$(sed -n 3p <<< "$v")" == *":$TEST_ROOT/work/" ]] || fail "up dest shown: $(printf %q "$v")"
slot="$HOME/.cache/up/$(sed -n 1p <<< "$v")"
[[ "$(stat -c %a "$slot")" == 700 ]] || fail "up slot not private"
up_answer "$v" ok report.pdf pdf
[[ "$up_rc" == 0 && "$(cat report.pdf)" == pdf ]] || fail "up: rc=$up_rc $(cat "$TEST_ROOT/up.err")"
[[ "$(stat -c %a report.pdf)" == "$(umask -S >/dev/null; printf '%o' $(( 0666 & ~8#$(umask) )))" ]] || fail "up mode $(stat -c %a report.pdf)"
[[ ! -e "$slot" ]] || fail "up left its slot"
up_start report.pdf; up_answer "$v" ok report.pdf again
[[ "$(cat 'report (1).pdf')" == again && "$(cat report.pdf)" == pdf ]] || fail "up overwrote"
# DEST: a directory keeps the name; anything else names the file.
mkdir -p sub
up_start x.txt sub; up_answer "$v" ok x.txt 1
[[ -f sub/x.txt ]] || fail "up into a directory"
up_start x.txt sub/y.txt; up_answer "$v" ok x.txt 2
[[ "$(cat sub/y.txt)" == 2 ]] || fail "up to a new name"
[[ "$(sed -n 3p <<< "$v")" == *":$TEST_ROOT/work/sub/y.txt" ]] || fail "up dest shown: $(printf %q "$v")"
# ~ is the Windows home, also when bash already expanded it here.
tilde='~'
up_start "$HOME/Desktop/n.txt"; up_answer "$v" cancel
[[ "$(sed -n 2p <<< "$v")" == "$tilde/Desktop/n.txt" ]] || fail "up ~: $(printf %q "$v")"
# Cancel and failure end up with exit 1, the reason, and no slot.
[[ "$up_rc" == 1 ]] || fail "up cancel: exit $up_rc"
grep -q 'cancelled' "$TEST_ROOT/up.err" || fail "up cancel: $(cat "$TEST_ROOT/up.err")"
up_start nope; up_answer "$v" 'fail: No such file: C:\x'
[[ "$up_rc" == 1 ]] || fail "up fail: exit $up_rc"
grep -q 'No such file: C:\\x' "$TEST_ROOT/up.err" || fail "up fail: $(cat "$TEST_ROOT/up.err")"
up_start; [[ "$(sed -n 2p <<< "$v")" == '' ]] || fail "up with no path: $(printf %q "$v")"
up_answer "$v" ok
[[ "$up_rc" == 1 ]] || fail "up ok without a file: exit $up_rc"
grep -q 'no file arrived' "$TEST_ROOT/up.err" || fail "up ok without a file: $(cat "$TEST_ROOT/up.err")"
[[ -z "$(ls -A "$HOME/.cache/up")" ]] || fail "up left slots: $(ls -A "$HOME/.cache/up")"
# Nothing answers: gives up, says how to scp instead, cleans up.
UP_TIMEOUT=1 setsid -w "$up" a.txt >/dev/null 2>"$TEST_ROOT/err" && fail "up timeout: exit 0"
grep -q "no answer from WezTerm in 1s.*scp FILE .*:$TEST_ROOT/work/" "$TEST_ROOT/err" || fail "up timeout: $(cat "$TEST_ROOT/err")"
[[ -z "$(ls -A "$HOME/.cache/up")" ]] || fail "up timeout left its slot"
# Refused before asking: a missing DEST directory, a line break, three words.
for args in "x nodir/y" "x nodir/" ; do
    # shellcheck disable=SC2086
    out="$(setsid -w "$up" $args 2>"$TEST_ROOT/err")" && fail "up $args: exit 0"
    [[ -z "$out" ]] || fail "up $args asked WezTerm"
    grep -q 'no such directory' "$TEST_ROOT/err" || fail "up $args: $(cat "$TEST_ROOT/err")"
done
setsid -w "$up" $'a\nb' >/dev/null 2>&1 && fail "up with a line break"
setsid -w "$up" a b c >/dev/null 2>&1 && fail "up with three words"
"$up" --help | grep -q '^Usage: up WINDOWS-PATH' || fail "up --help"

# --- Staged copies older than a day are pruned by the next run.
old="$HOME/.cache/dl/OLDOLDOLDOLD"
mkdir -p "$old"; touch -d '2 days ago' "$old"
run --print a.txt >/dev/null
[[ ! -e "$old" ]] || fail "old staging not pruned"

echo "dl: ok"
