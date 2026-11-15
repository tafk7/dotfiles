#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_BIN="$(command -v tmux)" || { echo 'tmux required for agent-badge tests' >&2; exit 1; }
TEST_ROOT="$(mktemp -d)"
SERVER="dotfiles-badge-$RANDOM-$$"
trap 'TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L "$SERVER" kill-server 2>/dev/null || true
      TMUX_TMPDIR="$TEST_ROOT/tmux" tmux -L default kill-server 2>/dev/null || true
      kill "${live:-}" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/tmux"
export TMUX_TMPDIR="$TEST_ROOT/tmux"

t() { "$TMUX_BIN" -L "$SERVER" "$@"; }
t -f /dev/null new-session -d -s test
t set-option -g window-status-format ' #I:#W '
t set-option -g window-status-current-format ' #I:#W '

mkdir -p "$TEST_ROOT/bin"
printf '#!/bin/sh\nexec %q -L %q "$@"\n' "$TMUX_BIN" "$SERVER" > "$TEST_ROOT/bin/tmux"
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

# A background session (`claude --bg`) has no pane: it names itself in
# AGENT_BADGE_SESSION, and its badge goes to whichever panes are viewing it --
# `claude attach <id|name>`, or the agent view showing it -- on the default
# server. Here "default" is a private server under this test's TMUX_TMPDIR, and
# perl rewrites its own command line to stand in for each viewer. Skipped
# without perl.
if command -v perl >/dev/null 2>&1; then
    d() { "$TMUX_BIN" -L default "$@"; }
    VHOME="$TEST_ROOT/home"
    mkdir -p "$VHOME/.claude/sessions"
    sleep 600 & live=$!
    sid1=1111aaaa-0000-4000-8000-000000000001
    sid2=2222bbbb-0000-4000-8000-000000000002
    session_file() {   # pid sid name status
        printf '{"pid":%s,"sessionId":"%s","jobId":"%s","name":"%s","kind":"bg","status":"%s"}\n' \
            "$1" "$2" "${2:0:8}" "$3" "$4" > "$VHOME/.claude/sessions/$5.json"
    }
    session_file "$live" "$sid1" probe-alpha busy one
    session_file "$live" "$sid2" probe-beta idle two
    viewer() {   # name, command line -> pane id
        d new-window -d -P -F '#{pane_id}' -n "$1" \
            "perl -e '\$0 = \"$2\"; sleep 600'"
    }
    # The server's HOME is the fixture's: once the first event wires it, its
    # own hooks (pane-title-changed) read session files too.
    HOME="$VHOME" "$TMUX_BIN" -L default -f /dev/null new-session -d -s v -x 120 -y 30
    p_id=$(viewer id 'claude attach 1111aaaa')
    p_name=$(viewer name 'claude attach ALPHA')
    p_amb=$(viewer amb 'claude attach probe')
    p_view=$(viewer view 'claude agents')
    d select-pane -t "$p_view" -T probe-alpha
    p_sh=$(d new-window -d -P -F '#{pane_id}' -n sh 'sleep 600')
    sleep 0.5
    vstate() { d show -p -t "$1" -qv @cc_pane_state; }
    vexpect() {   # pane, expected state, label; waits out background hooks
        local i
        for i in 1 2 3 4 5 6 7 8 9 10; do
            [[ "$(vstate "$1")" == "$2" ]] && return
            sleep 0.2
        done
        echo "FAIL: $3: got '$(vstate "$1")', want '$2'" >&2; exit 1
    }
    bg_status() {   # state, session
        env -u TMUX -u TMUX_PANE HOME="$VHOME" AGENT_BADGE_SESSION="$2" \
            bash "$ROOT/plugins/shared/scripts/agent-status.sh" "$1" '' </dev/null
    }
    reconcile() {   # the focus pass
        HOME="$VHOME" TMUX="$TMUX_TMPDIR/tmux-$(id -u)/default,0,0" \
            bash "$ROOT/plugins/shared/scripts/agent-reconcile.sh"
    }

    bg_status working "$sid1"
    vexpect "$p_id" working 'attach by short id'
    vexpect "$p_name" working 'attach by part of the name, any case'
    vexpect "$p_view" working 'agent view titled with the session name'
    vexpect "$p_amb" '' 'a name part matching two sessions'
    vexpect "$p_sh" '' 'a pane viewing nothing'
    [[ "$(d show -p -t "$p_id" -qv @cc_pane_session)" == "$sid1" ]] \
        || { echo 'FAIL: viewer pane not tagged with its session' >&2; exit 1; }
    [[ -n "$(d show -w -t "$p_id" -qv @cc_win_badge)" ]] \
        || { echo 'FAIL: viewer window has no badge' >&2; exit 1; }
    bg_status working "$sid2"
    vexpect "$p_view" working 'the other session left the agent-view pane alone'
    bg_status gone "$sid1"
    vexpect "$p_id" '' 'session end clears its viewers'

    # Seeding: a viewer the hooks never wrote takes the session file's status;
    # waiting is a permission prompt on screen.
    session_file "$live" "$sid1" probe-alpha waiting one
    reconcile
    vexpect "$p_id" needs 'seeded waiting'
    vexpect "$p_amb" '' 'seeding an ambiguous viewer'
    # The reconciler reaches a seeded pane by its session tag: busy demotes needs.
    session_file "$live" "$sid1" probe-alpha busy one
    reconcile
    vexpect "$p_id" working 'busy demotes a seeded needs'
    # A hook-written state is never promoted by the file.
    d set -p -t "$p_name" @cc_pane_state 'done'
    reconcile
    vexpect "$p_name" 'done' 'seeding overwrote a hook-written state'

    # The agent view switching sessions reseeds through the pane-title-changed
    # hook the first event wired; back on its list it clears.
    d select-pane -t "$p_view" -T probe-beta
    vexpect "$p_view" idle 'agent view switched to an idle session'
    [[ "$(d show -p -t "$p_view" -qv @cc_pane_session)" == "$sid2" ]] \
        || { echo 'FAIL: agent view kept the old session tag' >&2; exit 1; }
    [[ -n "$(d show-hooks -g pane-title-changed)" ]] \
        || { echo 'FAIL: a background event did not wire the server' >&2; exit 1; }
    d select-pane -t "$p_view" -T 'host: claude agents'
    vexpect "$p_view" '' 'agent view back on its list'

    # A dead session is never seeded.
    d set -pu -t "$p_id" @cc_pane_state
    d set -pu -t "$p_id" @cc_pane_session
    session_file 999999999 "$sid1" probe-alpha busy one
    reconcile
    vexpect "$p_id" '' 'seeded from a dead session'

    d kill-server
    kill "$live" 2>/dev/null
else
    echo 'agent-badge: skipped background-viewer tests (perl not found)'
fi

# A standalone plugin installation without jq must give a clear diagnostic,
# never emit hook protocol output or fail the calling agent session.
PATH="$TEST_ROOT/bin" TMUX=test TMUX_PANE=%1 \
    "$ROOT/plugins/shared/scripts/agent-status.sh" session-start \
    > "$TEST_ROOT/hook.out" 2> "$TEST_ROOT/hook.err"
[[ ! -s "$TEST_ROOT/hook.out" ]] || { echo 'FAIL: hook wrote stdout' >&2; exit 1; }
grep -Fq 'jq is required on PATH' "$TEST_ROOT/hook.err" \
    || { echo 'FAIL: missing jq was silent' >&2; exit 1; }

# The Claude side is a mod; run its own tests when this claude can load mods.
if command -v claude >/dev/null 2>&1 \
   && [[ "$(claude --version 2>/dev/null | awk '{print $1}' | tr -d '\n')" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
   && [[ "$(printf '2.1.287\n%s\n' "$(claude --version | awk '{print $1}')" | sort -V | head -1)" == 2.1.287 ]]; then
    claude plugin validate --strict "$ROOT/plugins/agent-badge-claude" >/dev/null \
        || { echo 'FAIL: agent-badge-claude fails plugin validate' >&2; exit 1; }
    claude plugin test "$ROOT/plugins/agent-badge-claude" >/dev/null \
        || { echo 'FAIL: agent-badge-claude mod tests failed' >&2; exit 1; }
else
    echo 'agent-badge: skipped mod tests (claude >= 2.1.287 not found)'
fi

printf 'agent-badge: ok\n'
