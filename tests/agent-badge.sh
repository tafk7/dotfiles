#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
SERVER="dotfiles-badge-$RANDOM-$$"
trap 'TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" kill-server 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/tmux"
export TMUX_TMPDIR="$TEST_ROOT/tmux"

t() { /usr/bin/tmux -L "$SERVER" "$@"; }
t -f /dev/null new-session -d -s test
t set-option -g window-status-format ' #I:#W '
t set-option -g window-status-current-format ' #I:#W '

mkdir -p "$TEST_ROOT/bin"
printf '#!/bin/sh\nexec /usr/bin/tmux -L %q "$@"\n' "$SERVER" > "$TEST_ROOT/bin/tmux"
chmod +x "$TEST_ROOT/bin/tmux"
PATH="$TEST_ROOT/bin:$PATH" TMUX=test "$ROOT/plugins/shared/agent-badge.tmux" wire
[[ "$(t show-options -gv window-status-format)" == *'@cc_win_badge'* ]] \
    || { echo 'FAIL: badge format was not wired' >&2; exit 1; }
[[ "$(t show-hooks -g pane-focus-in)" == *'agent-reconcile.sh'* ]] \
    || { echo 'FAIL: badge hooks were not wired' >&2; exit 1; }

# A cache upgrade must repair hook paths even though the badge format survived.
# Keep an unrelated hook in the same array to verify scoped replacement.
t set-hook -ga pane-focus-in 'set-option -g @unrelated_hook preserved'
old="$TEST_ROOT/cache one"
new="$TEST_ROOT/cache two's"
cp -R "$ROOT/plugins/shared" "$old"
cp -R "$ROOT/plugins/shared" "$new"
PATH="$TEST_ROOT/bin:$PATH" TMUX=test "$old/agent-badge.tmux" wire
pane=$(t display-message -p -t test '#{pane_id}')

# Execute the real tmux-parsed shell payloads with a present and a removed cache.
# This catches both command-not-found failures and quoting errors in cache paths.
check_hook_commands() {
    t show-hooks -g pane-focus-in > "$TEST_ROOT/hooks.txt"
    PATH="$TEST_ROOT/bin:$PATH" TMUX=test python3 - "$TEST_ROOT/hooks.txt" "$pane" <<'PY'
import pathlib, shlex, subprocess, sys
commands = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if 'agent-status.sh' in line or 'agent-reconcile.sh' in line:
        words = shlex.split(line.split(' ', 1)[1])
        assert words[:2] == ['run-shell', '-b'], words
        commands.append(words[2].replace('#{pane_id}', sys.argv[2]))
assert len(commands) == 3, commands
for command in commands:
    result = subprocess.run(['sh', '-c', command], capture_output=True, text=True)
    assert result.returncode == 0, (command, result.returncode, result.stderr)
    assert not result.stderr, (command, result.stderr)
PY
}
check_hook_commands
rm -rf "$old"
check_hook_commands

# Reproduce the stale pre-upgrade marker with a still-visible badge.
t set-option -g @cc_badge_wiring_version 1
printf '{"source":"startup"}' | PATH="$TEST_ROOT/bin:$PATH" TMUX=test TMUX_PANE="$pane" \
    "$new/scripts/agent-status.sh" session-start
[[ "$(t show-options -gv @cc_badge_wired)" == "$new" ]] \
    || { echo 'FAIL: SessionStart kept the old cache despite a visible badge' >&2; exit 1; }
[[ "$(t show-hooks -g pane-focus-in)" != *"$old"* ]] \
    || { echo 'FAIL: obsolete cache path remains' >&2; exit 1; }
[[ "$(t show-hooks -g pane-focus-in)" == *'@unrelated_hook'* ]] \
    || { echo 'FAIL: repair removed an unrelated hook' >&2; exit 1; }
check_hook_commands
before=$(t show-hooks -g pane-focus-in)
PATH="$TEST_ROOT/bin:$PATH" TMUX=test "$new/agent-badge.tmux" wire
[[ "$(t show-hooks -g pane-focus-in)" == "$before" ]] \
    || { echo 'FAIL: repeated wiring duplicated or changed hooks' >&2; exit 1; }

PATH="$TEST_ROOT/bin:$PATH" TMUX=test "$ROOT/plugins/shared/agent-badge.tmux" unwire
[[ "$(t show-options -gv window-status-format)" != *'@cc_win_badge'* ]] \
    || { echo 'FAIL: badge format was not unwired' >&2; exit 1; }
[[ "$(t show-hooks -g pane-focus-in)" != *'agent-reconcile.sh'* ]] \
    || { echo 'FAIL: badge hook was not unwired' >&2; exit 1; }

# A standalone plugin installation without jq must give a clear diagnostic,
# never emit hook protocol output or fail the calling agent session.
PATH="$TEST_ROOT/bin" TMUX=test TMUX_PANE=%1 \
    "$ROOT/plugins/shared/scripts/agent-status.sh" session-start \
    > "$TEST_ROOT/hook.out" 2> "$TEST_ROOT/hook.err"
[[ ! -s "$TEST_ROOT/hook.out" ]] || { echo 'FAIL: hook wrote stdout' >&2; exit 1; }
grep -Fq 'jq is required on PATH' "$TEST_ROOT/hook.err" \
    || { echo 'FAIL: missing jq was silent' >&2; exit 1; }

printf 'agent-badge: ok\n'
