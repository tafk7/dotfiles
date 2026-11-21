#!/bin/bash
# bin/dl: lookup (here, then DL_PATH), staging into a private ~/.cache/dl with
# names the WezTerm side accepts, the dl_fetch user variable (plain and wrapped
# for tmux), pruning, and the --print / --wezterm-config forms WezTerm uses.
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
uservar() {   # decode the dl_fetch value(s) in "$1"
    grep -o 'SetUserVar=dl_fetch=[A-Za-z0-9+/=]*' <<< "$1" | while IFS= read -r v; do
        printf '%s\n' "${v#SetUserVar=dl_fetch=}" | base64 -d; echo
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

# --- Staged copies older than a day are pruned by the next run.
old="$HOME/.cache/dl/OLDOLDOLDOLD"
mkdir -p "$old"; touch -d '2 days ago' "$old"
run --print a.txt >/dev/null
[[ ! -e "$old" ]] || fail "old staging not pruned"

echo "dl: ok"
