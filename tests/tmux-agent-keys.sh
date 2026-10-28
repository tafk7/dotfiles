#!/bin/bash
# The intent keys tmux translates for each agent (issues/intent-keys.md):
# Shift+Tab steps the permission mode through the three in use, Ctrl+Shift+Tab
# hands the agent a plain Shift+Tab, the Queue key queues a message, Break
# stops whatever runs, Ctrl+Z undoes typing, and Alt+Shift+V opens a program's
# own editor.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

SHIFT_TAB='\e[Z'
CTRL_SHIFT_TAB='\e[27;6;9~'
QUEUE='\e[19;2~'
BREAK='\e[20;2~'
ALT_SHIFT_V='\eV'

tk_start

# A stub under NAME in a new window; prints its pane id once it is running.
stub() {
    local name="$1" log="$2" pane
    shift 2
    pane=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub "$name" "$log" "$@")")
    tk_ready "$log"
    tk_wait '#{pane_current_command}' "$name" "$pane"
    printf '%s' "$pane"
}
footer() { tk_until tk_screen_has "$1 on" "$2" || fail "footer never showed '$1 on': $(ti capture-pane -p -t "$2" | tail -n 1)"; }
presses() { tk_input "$1" | grep -o '\^\[\[Z' | wc -l; }

# Claude: Shift+Tab goes accept edits, bypass, auto, skipping plan and manual
# mode; Ctrl+Shift+Tab is one plain step.
claude_log="$TEST_ROOT/claude.log"
claude=$(stub claude "$claude_log" --modes ',accept edits,plan mode,bypass permissions,auto mode')
tk_raw "$SHIFT_TAB"
footer 'accept edits' "$claude"
tk_raw "$SHIFT_TAB"
footer 'bypass permissions' "$claude"
tk_raw "$SHIFT_TAB"
footer 'auto mode' "$claude"
tk_raw "$SHIFT_TAB"
footer 'accept edits' "$claude"
sleep 0.3
assert_eq "$(presses "$claude_log")" 6 "Shift+Tab presses sent to Claude"
tk_raw "$CTRL_SHIFT_TAB"
footer 'plan mode' "$claude"
sleep 0.3
assert_eq "$(presses "$claude_log")" 7 "Ctrl+Shift+Tab sent more than one Shift+Tab"

# Without bypass or auto, a whole cycle comes back to accept edits.
lean_log="$TEST_ROOT/lean.log"
lean=$(stub claude "$lean_log" --modes 'accept edits,plan mode,')
tk_raw "$SHIFT_TAB"
sleep 1
footer 'accept edits' "$lean"
assert_eq "$(presses "$lean_log")" 3 "Shift+Tab presses in a Claude without bypass or auto"

# Codex gets F7, its next_permission_mode; anything else the key as it is.
codex_log="$TEST_ROOT/codex.log"
codex=$(stub codex "$codex_log")
tk_raw "$SHIFT_TAB"
tk_expect '^[[18~' "Shift+Tab in Codex" tk_input "$codex_log"
tk_raw "$CTRL_SHIFT_TAB"
tk_expect '^[[18~^[[Z' "Ctrl+Shift+Tab in Codex" tk_input "$codex_log"
app_log="$TEST_ROOT/app.log"
app=$(stub app "$app_log")
tk_raw "$SHIFT_TAB"
tk_expect '^[[Z' "Shift+Tab in another program" tk_input "$app_log"

# Queue: each agent's key for a message after the turn; nothing elsewhere.
for agent in claude codex opencode pi; do
    log="$TEST_ROOT/queue-$agent.log"
    stub "$agent" "$log" >/dev/null
    tk_raw "$QUEUE"
    case "$agent" in
        claude | opencode) want='^X^M' ;;
        codex) want='^I' ;;
        pi) want='^[^M' ;;
    esac
    tk_expect "$want" "Queue key in $agent" tk_input "$log"
done
ti select-window -t "$(ti display-message -p -t "$app" '#{window_id}')"
: > "$app_log"
tk_raw "${QUEUE}x"
tk_expect 'x' "Queue key in another program" tk_input "$app_log"

# Break: Esc to an agent, Ctrl+C to anything else.
: > "$app_log"
tk_raw "$BREAK"
tk_expect '^C' "Break in another program" tk_input "$app_log"
pi_log="$TEST_ROOT/pi.log"
pi=$(stub pi "$pi_log")
tk_raw "${BREAK}x"
tk_expect '^[x' "Break in pi" tk_input "$pi_log"

# Ctrl+Z: Claude's undo is Ctrl+_; elsewhere the key goes on.
ti select-window -t "$(ti display-message -p -t "$claude" '#{window_id}')"
: > "$claude_log"
tk_raw '\032'
tk_expect '^_' "Ctrl+Z in Claude" tk_input "$claude_log"
ti select-window -t "$(ti display-message -p -t "$app" '#{window_id}')"
: > "$app_log"
tk_raw '\032'
tk_expect '^Z' "Ctrl+Z in another program" tk_input "$app_log"

# Alt+Shift+V with no compose-editor: the program's own editor key; nothing in
# a program without one.
: > "$pi_log"
ti select-window -t "$(ti display-message -p -t "$pi" '#{window_id}')"
tk_raw "$ALT_SHIFT_V"
tk_expect '^G' "Alt+Shift+V in pi" tk_input "$pi_log"
bash_log="$TEST_ROOT/bash.log"
stub bash "$bash_log" >/dev/null
tk_raw "$ALT_SHIFT_V"
tk_expect '^X^E' "Alt+Shift+V in a shell" tk_input "$bash_log"
ti select-window -t "$(ti display-message -p -t "$app" '#{window_id}')"
: > "$app_log"
tk_raw "${ALT_SHIFT_V}x"
tk_expect 'x' "Alt+Shift+V in another program" tk_input "$app_log"

printf 'tmux-agent-keys: ok\n'
