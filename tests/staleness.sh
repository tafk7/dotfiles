#!/bin/bash
# Staleness: shells that loaded before a change dotfiles made are listed until
# they reload, a soft reload stays stale, a reused pid is not the same shell, a
# hand edit makes shells "possibly stale", and a program started before its
# consumer changed is listed on every report until it restarts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
fixture_init
pids=()
trap 'kill "${pids[@]}" 2>/dev/null || true; fixture_cleanup' EXIT
export XDG_RUNTIME_DIR="$TEST_ROOT/run"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME/dotfiles"
source "$ROOT/lib/install.sh"
source "$ROOT/lib/outcomes.sh"
source "$ROOT/lib/staleness.sh"
shells="$XDG_RUNTIME_DIR/dotfiles/shells"
report() { staleness_report "$@" 2>/dev/null; }
loaded_of() { cut -f1 "$shells/$1-$(proc_start_ticks "$1")"; }
wait_record() { for _ in $(seq 50); do [[ -n "$(ls "$shells"/"$1"-* 2>/dev/null)" ]] && return; sleep 0.1; done; fail "no record for $1"; }

# A shell loads (records itself), then a pull changes shell startup.
bash -c 'source "$1/shell/staleness.sh"; exec sleep 60' _ "$ROOT" &
old_shell=$!; pids+=("$old_shell"); wait_record "$old_shell"
change_record shell "pulled a..b" "$(( $(loaded_of "$old_shell") + 1 ))"
out="$(report)"
[[ "$out" == *"1 loaded before the last change to shell startup (pulled a..b); reload them: pids $old_shell"* ]] \
    || fail "a shell older than the change was not listed: $out"
[[ "$(report)" == *"pids $old_shell"* ]] || fail "a second report forgot the stale shell"

# A soft reload after the change keeps the shell stale; a real reload clears it.
change_record shell "pulled b..c" "$(( $(date +%s) - 50 ))"
bash -c 'source "$1/shell/staleness.sh"; sleep 2; _DOTFILES_SOFT_RELOAD=1; source "$1/shell/staleness.sh"; exec sleep 60' _ "$ROOT" &
soft_shell=$!; pids+=("$soft_shell"); wait_record "$soft_shell"
sleep 0.2
change_record shell "pulled c..d" "$(( $(loaded_of "$soft_shell") + 1 ))"
sleep 2.5
[[ "$(cut -f2 "$shells/$soft_shell-$(proc_start_ticks "$soft_shell")")" == soft ]] || fail "the soft reload was not marked"
[[ "$(report)" == *"1 soft-reloaded after the last change"*"pids $soft_shell"* ]] || fail "a soft reload looked current: $(report)"
change_record shell "pulled d..e" "$(( $(date +%s) - 50 ))"
bash -c 'source "$1/shell/staleness.sh"; exec sleep 60' _ "$ROOT" &
fresh_shell=$!; pids+=("$fresh_shell"); wait_record "$fresh_shell"
[[ "$(report)" != *"$fresh_shell"* ]] || fail "a shell loaded after the change was listed: $(report)"

# A record whose pid now belongs to another process is not that shell.
printf '%s\tfull\n' 1 > "$shells/$$-1"
[[ "$(report)" != *"pids $$"* ]] || fail "a reused pid was taken for the recorded shell"
report --sweep >/dev/null
[[ ! -e "$shells/$$-1" ]] || fail "refresh's sweep kept a dead record"

# A hand edit after a shell loaded: possibly stale.
printf 'alias x=y\n' > "$HOME/.shell.local"
touch -d "@$(( $(date +%s) + 100 ))" "$HOME/.shell.local"
[[ "$(report)" == *"possibly stale: ~/.shell.local or ~/.shell.env changed after they loaded: pids"*"$fresh_shell"* ]] \
    || fail "a hand edit was not reported: $(report)"

# A program started before its consumer changed, on every report.
cp "$(command -v sleep)" "$TEST_ROOT/claude"
"$TEST_ROOT/claude" 60 &
program=$!; pids+=("$program")
change_record claude "claude installed" "$(( $(date +%s) + 100 ))"
# (This host's own claude processes may be listed too.)
for _ in 1 2; do
    line="$(report | grep $'^advisory\tRunning\tclaude\t' || true)"
    [[ "$line" == *"started before claude changed (claude installed); restart them: pids "* && " ${line##*pids } " == *" $program "* ]] \
        || fail "a stale program was not listed: $(report)"
done

# Codex's app-server daemon outlives a restart in a pane; the line says how
# to restart it.
mkdir -p "$TEST_ROOT/app-server"
cp "$(command -v sleep)" "$TEST_ROOT/app-server/codex"
"$TEST_ROOT/app-server/codex" 60 &
daemon=$!; pids+=("$daemon")
change_record codex "codex settings changed" "$(( $(date +%s) + 100 ))"
line="$(report | grep $'^advisory\tRunning\tcodex\t' || true)"
[[ " ${line#*pids } " == *" $daemon "* && "$line" == *"(its background server: codex app-server daemon restart)"* ]] \
    || fail "the Codex daemon's restart was not named: $line"

# No runtime directory: the limit is reported, not taken as current.
[[ "$(XDG_RUNTIME_DIR='' staleness_report 2>/dev/null)" == *"not tracked: XDG_RUNTIME_DIR is unset"* ]] || fail "missing runtime dir"

printf 'staleness: ok\n'
