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
