#!/bin/bash
# Keys tmux translates for Claude: Ctrl+C becomes Esc, which spares its
# background agents, and Ctrl/Alt+Backspace/Delete become the keys Claude has
# for deleting a word or to the line's start or end. Other panes, and Claude in
# copy-mode, get the keys unchanged; prefix+Ctrl+C is a real Ctrl+C.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

PREFIX='\001'

tk_start

# expect_key LOG BYTES WANT LABEL: the pane logging to LOG receives WANT for
# the client input BYTES.
expect_key() {
    : > "$1"
    tk_raw "$2x"
    tk_until grep -q x "$1" || fail "$4: no input"
    assert_eq "$(tk_input "$1")" "$3x" "$4"
}

claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$claude_log" --alt)")
tk_ready "$claude_log"
tk_wait '#{pane_current_command}' claude
expect_key "$claude_log" '\003' '^[' "Ctrl+C in Claude"
expect_key "$claude_log" "${PREFIX}"'\003' '^C' "prefix+Ctrl+C in Claude"
expect_key "$claude_log" '\b' '^[^?' "Ctrl+Backspace in Claude"
expect_key "$claude_log" '\e[127;5u' '^[^?' "extended Ctrl+Backspace in Claude"
expect_key "$claude_log" '\e[3;5~' '^[d' "Ctrl+Delete in Claude"
expect_key "$claude_log" '\e\177' '^U' "Alt+Backspace in Claude"
expect_key "$claude_log" '\e[3;3~' '^K' "Alt+Delete in Claude"

# In copy-mode the keys go to copy-mode: Ctrl+C leaves it, nothing reaches Claude.
: > "$claude_log"
ti copy-mode -t "$claude"
tk_raw '\003'
tk_wait '#{pane_in_mode}' 0 "$claude"
tk_raw z
tk_until grep -q z "$claude_log" || fail "Claude stub got no input"
assert_eq "$(tk_input "$claude_log")" 'z' "Ctrl+C in a Claude pane's copy-mode"

app_log="$TEST_ROOT/app.log"
ti new-window -t test "$(tk_stub app "$app_log")"
tk_ready "$app_log"
tk_wait '#{pane_current_command}' app
expect_key "$app_log" '\003' '^C' "Ctrl+C outside Claude"
expect_key "$app_log" '\b' '^H' "Ctrl+Backspace outside Claude"
expect_key "$app_log" '\e[127;5u' '^H' "extended Ctrl+Backspace outside Claude"
expect_key "$app_log" '\e[3;5~' '^[[3;5~' "Ctrl+Delete outside Claude"
expect_key "$app_log" '\e\177' '^[^?' "Alt+Backspace outside Claude"
expect_key "$app_log" '\e[3;3~' '^[[3;3~' "Alt+Delete outside Claude"

printf 'tmux-claude-keys: ok\n'
