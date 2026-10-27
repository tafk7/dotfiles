#!/bin/bash
# The raw-key harness against the bindings it was built for: the Copy key in
# copy-mode, in Claude, in Codex, and in a shell; the review key; the Pause key.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

COPY='\e[2;5~'
REVIEW='\e[15;2~'
PAUSE='\e[17;2~'

tk_start

# Copy in copy-mode copies the selection to the tmux buffer.
ti respawn-pane -k -t test "printf 'alpha beta gamma\n'; exec sleep 3600"
tk_until tk_screen_has gamma test || fail "fixture text never appeared"
ti copy-mode -t test
ti send -X -t test search-backward alpha
ti send -X -t test begin-selection
ti send -X -t test end-of-line
tk_raw "$COPY"
tk_wait '#{pane_in_mode}' 0 test
assert_eq "$(ti show-buffer)" "alpha beta gamma" "Copy key in copy-mode"

# In Claude the key arrives as Ctrl+Shift+C (selection:copy), and only while
# Claude reads extended keys: as a plain Ctrl+C it would interrupt. In any other
# pane it is swallowed.
claude_log="$TEST_ROOT/claude.log"
ti new-window -t test "$(tk_stub claude "$claude_log" --extkeys)"
tk_ready "$claude_log"
tk_wait '#{pane_current_command}' claude
if [[ -n "$(ti display-message -p '#{pane_key_mode}')" ]]; then
    tk_wait '#{pane_key_mode}' 'Ext 2'
    tk_raw "${COPY}x"
    tk_until grep -q x "$claude_log" || fail "Claude stub got no input"
    assert_eq "$(tk_input "$claude_log")" '^[[27;6;99~x' "Copy key in Claude"
else
    tk_raw "${COPY}x"
    tk_until grep -q x "$claude_log" || fail "Claude stub got no input"
    assert_eq "$(tk_input "$claude_log")" 'x' "Copy key in Claude without pane_key_mode"
fi

plain_log="$TEST_ROOT/claude-plain.log"
ti new-window -t test "$(tk_stub claude "$plain_log")"
tk_ready "$plain_log"
tk_wait '#{pane_current_command}' claude
tk_raw "${COPY}x"
tk_until grep -q x "$plain_log" || fail "Claude stub got no input"
assert_eq "$(tk_input "$plain_log")" 'x' "Copy key in Claude without extended keys"

# Codex copies its own selection (Ctrl+Space or mouse) with the key as it is.
codex_log="$TEST_ROOT/codex.log"
ti new-window -t test "$(tk_stub codex "$codex_log")"
tk_ready "$codex_log"
tk_wait '#{pane_current_command}' codex
tk_raw "${COPY}x"
tk_until grep -q x "$codex_log" || fail "Codex stub got no input"
assert_eq "$(tk_input "$codex_log")" '^[[2;5~x' "Copy key in Codex"

app_log="$TEST_ROOT/app.log"
ti new-window -t test "$(tk_stub app "$app_log")"
tk_ready "$app_log"
tk_wait '#{pane_current_command}' app
tk_raw "${COPY}x"
tk_until grep -q x "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" 'x' "Copy key outside Claude"

# The review key toggles copy-mode from either side.
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 0
assert_eq "$(tk_input "$app_log")" 'x' "review key leaked to the app"

# Pause stays in tmux (it toggles clipboard export).
tk_raw "${PAUSE}y"
tk_until grep -q y "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" 'xy' "Pause key leaked to the app"

printf 'tmux-keys-selftest: ok\n'
