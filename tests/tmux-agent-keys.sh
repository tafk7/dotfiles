#!/bin/bash
# The intent keys tmux translates for each agent (issues/intent-keys.md):
# Alt+Shift+J, K and L put it in yolo, auto or edits-only mode (Shift+Tab
# stays its own), Alt+Enter queues a message and Alt+Shift+Enter takes it
# back, Shift+Enter is a new line, Alt+Z goes back a turn, Break stops
# whatever runs, Ctrl+Z undoes typing, and Alt+Shift+V opens a program's own
# editor.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

SHIFT_TAB='\e[Z'
YOLO='\eJ'
AUTO='\eK'
EDITS='\eL'
QUEUE='\e\r'
UNQUEUE='\e[27;4;13~'
SHIFT_ENTER='\e[27;2;13~'
UNDO_TURN='\ez'
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
on_screen() { tk_until tk_screen_has "$1" "$2" || fail "$3 never showed '$1': $(ti capture-pane -p -t "$2" | grep . | tail -n 3)"; }
footer() { on_screen "$1 on" "$2" "Claude's footer"; }
count() { tk_input "$2" | grep -o -F -- "$1" | wc -l; }
presses() { count '^[[Z' "$1"; }
# Whether Codex's transcript notes switching to $2 $1 times.
codex_switched() { [[ "$(ti capture-pane -p -t "$codex" | grep -c -F "requested: $2")" == "$1" ]]; }
switched() { tk_until codex_switched "$1" "$2" || fail "Codex never switched to $2 $1 times"; }
said() { tk_until tk_contains "$1" ti show-messages || fail "tmux never said '$1'"; }

# Claude: Shift+Tab is its own cycle, one step a press; Alt+Shift+J, K and L
# step it to bypass permissions, auto mode and accept edits.
claude_log="$TEST_ROOT/claude.log"
claude=$(stub claude "$claude_log" --modes ',accept edits,plan mode,bypass permissions,auto mode')
tk_raw "$SHIFT_TAB"
footer 'accept edits' "$claude"
tk_raw "$SHIFT_TAB"
footer 'plan mode' "$claude"
assert_eq "$(presses "$claude_log")" 2 "Shift+Tab presses sent to Claude"
tk_raw "$YOLO"
footer 'bypass permissions' "$claude"
tk_raw "$AUTO"
footer 'auto mode' "$claude"
tk_raw "$EDITS"
footer 'accept edits' "$claude"
said 'Claude: accept edits'
assert_eq "$(presses "$claude_log")" 6 "Shift+Tab presses for bypass, auto, then accept edits"
tk_raw "$EDITS"
sleep 0.5
assert_eq "$(presses "$claude_log")" 6 "Alt+Shift+L pressed Shift+Tab in accept edits"

# Without bypass, Alt+Shift+J goes round once and leaves the mode as it was.
lean_log="$TEST_ROOT/lean.log"
lean=$(stub claude "$lean_log" --modes 'accept edits,plan mode,')
tk_raw "$YOLO"
said 'Claude has no bypass permissions in this session'
footer 'accept edits' "$lean"
assert_eq "$(presses "$lean_log")" 3 "Shift+Tab presses in a Claude without bypass"

# Codex with an empty prompt: /permissions and its picker, Full Access
# confirmed.
codex_log="$TEST_ROOT/codex.log"
codex=$(stub codex "$codex_log" --codex-modes)
tk_raw "$AUTO"
switched 1 'Approve for me'
tk_raw "$YOLO"
switched 1 'Full Access'
said 'Codex: Full Access'
tk_raw "$YOLO"
typed() { [[ "$(count /permissions "$codex_log")" == 3 ]]; }
tk_until typed || fail "Alt+Shift+J in Full Access never opened /permissions"
sleep 0.5
switched 1 'Full Access'
on_screen 'Ask Codex to do anything' "$codex" Codex
# With a draft, F7 instead: the picker on its first press, then its cycle;
# Full Access isn't in the cycle, so Alt+Shift+J leaves it alone.
tk_raw 'draft'
on_screen '› draft' "$codex" Codex
tk_raw "$EDITS"
switched 1 'Ask for approval'
tk_raw "$AUTO"
switched 2 'Approve for me'
assert_eq "$(count '^[[18~' "$codex_log")" 2 "F7 presses in Codex"
tk_raw "$YOLO"
said 'Codex: Full Access is only in /permissions; empty the prompt first'
on_screen '› draft' "$codex" Codex
assert_eq "$(count '/permissions' "$codex_log")" 3 "/permissions typed with a draft"
tk_raw "$SHIFT_TAB"
tk_until tk_contains '^[[Z' tk_input "$codex_log" || fail "Shift+Tab never reached Codex"

# OpenCode: Ctrl+P, Permissions, one flip, and only when it differs.
opencode_log="$TEST_ROOT/opencode.log"
opencode=$(stub opencode "$opencode_log" --opencode-modes)
tk_raw "$YOLO"
on_screen 'Build auto · ' "$opencode" OpenCode
said 'OpenCode: auto accept, in every session'
tk_raw "$YOLO"
said 'OpenCode: auto accept'
tk_raw "$AUTO"
said 'OpenCode has no auto mode'
tk_raw "$EDITS"
on_screen 'Build · ' "$opencode" OpenCode
assert_eq "$(count '^P' "$opencode_log")" 2 "Ctrl+P presses in OpenCode"

# pi gets nothing; anything else gets the keys as they are.
pi_mode_log="$TEST_ROOT/pi-mode.log"
stub pi "$pi_mode_log" >/dev/null
tk_raw "$YOLO"
said 'pi runs everything without asking'
assert_eq "$(tk_input "$pi_mode_log")" '' "keys sent to pi"
app_log="$TEST_ROOT/app.log"
app=$(stub app "$app_log")
tk_raw "$SHIFT_TAB$YOLO$AUTO$EDITS"
tk_expect '^[[Z^[J^[K^[L' "Shift+Tab and Alt+Shift+J, K, L in another program" tk_input "$app_log"

# Alt+Enter queues, Alt+Shift+Enter takes back, Alt+Z goes back a turn: each
# agent's own keys; anything else gets the keys as they are.
for agent in claude codex opencode pi; do
    log="$TEST_ROOT/queue-$agent.log"
    stub "$agent" "$log" >/dev/null
    tk_raw "$QUEUE"
    case "$agent" in
        claude | opencode) want='^X^M' ;;
        codex) want='^I' ;;
        pi) want='^[^M' ;;
    esac
    tk_expect "$want" "Alt+Enter in $agent" tk_input "$log"
    : > "$log"
    tk_raw "$UNQUEUE"
    case "$agent" in
        claude) want='^[[A' ;;
        codex) want='^[[1;2D' ;;
        opencode) want='^Xq' ;;
        pi) want='^[[1;3A' ;;
    esac
    tk_expect "$want" "Alt+Shift+Enter in $agent" tk_input "$log"
    : > "$log"
    tk_raw "$UNDO_TURN"
    case "$agent" in
        claude | codex) want='^[^[' ;;
        opencode) want='^Xu' ;;
        pi) want='^[z' ;;
    esac
    tk_expect "$want" "Alt+Z in $agent" tk_input "$log"
    if [[ "$agent" == codex ]]; then
        : > "$log"
        tk_raw "${SHIFT_ENTER}x"
        tk_expect $'\nx' "Shift+Enter in Codex (Ctrl+J)" tk_input "$log"
    fi
done
ti select-window -t "$(ti display-message -p -t "$app" '#{window_id}')"
: > "$app_log"
tk_raw "${QUEUE}${UNDO_TURN}x"
tk_expect '^[^M^[zx' "Alt+Enter and Alt+Z in another program" tk_input "$app_log"
: > "$app_log"
tk_raw "${SHIFT_ENTER}x"
tk_expect '^Mx' "Shift+Enter in another program" tk_input "$app_log"

# Break: Esc to an agent, Ctrl+C to anything else.
: > "$app_log"
tk_raw "$BREAK"
tk_expect '^C' "Break in another program" tk_input "$app_log"
pi_log="$TEST_ROOT/pi.log"
pi=$(stub pi "$pi_log")
tk_raw "${BREAK}x"
tk_expect '^[x' "Break in pi" tk_input "$pi_log"

# Ctrl+Z: Claude's undo is Ctrl+_; Codex, which would suspend, gets nothing;
# elsewhere the key goes on.
ti select-window -t "$(ti display-message -p -t "$claude" '#{window_id}')"
: > "$claude_log"
tk_raw '\032'
tk_expect '^_' "Ctrl+Z in Claude" tk_input "$claude_log"
ti select-window -t "$(ti display-message -p -t "$app" '#{window_id}')"
: > "$app_log"
tk_raw '\032'
tk_expect '^Z' "Ctrl+Z in another program" tk_input "$app_log"
codex_z_log="$TEST_ROOT/codex-z.log"
stub codex "$codex_z_log" >/dev/null
tk_raw '\032x'
tk_expect 'x' "Ctrl+Z in Codex" tk_input "$codex_z_log"
said 'Codex has no undo'

# prefix+Ctrl+Z suspends: Claude and Codex get the key, which suspends them;
# anything else in the foreground is sent SIGTSTP (bin/tmux-suspend).
ti select-window -t "$(ti display-message -p -t "$claude" '#{window_id}')"
: > "$claude_log"
tk_raw '\001\032'
tk_expect '^Z' "prefix+Ctrl+Z in Claude" tk_input "$claude_log"
job=$(ti new-window -t test -P -F '#{pane_id}' 'bash --norc --noprofile -i')
tk_wait '#{pane_current_command}' bash "$job"
ti send-keys -t "$job" 'sleep 300' Enter
tk_wait '#{pane_current_command}' sleep "$job"
sleeper=$(pgrep -P "$(ti display-message -p -t "$job" '#{pane_pid}')" -x sleep)
tk_raw '\001\032'
stopped() { [[ "$(ps -o stat= -p "$sleeper" | tr -d ' ')" == T* ]]; }
tk_until stopped || fail "prefix+Ctrl+Z did not suspend the foreground job"
on_screen 'Stopped' "$job" "the shell"
kill -KILL "$sleeper" 2>/dev/null || true

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
