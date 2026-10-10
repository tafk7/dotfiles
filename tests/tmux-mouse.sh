#!/bin/bash
# A click on an inactive pane only focuses it; the application sees nothing
# until the pane is active. Ctrl+click reaches the application.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

tk_start

app_log="$TEST_ROOT/app.log"
right=$(ti split-window -h -t test -P -F '#{pane_id}' "$(tk_stub app "$app_log" --mouse)")
tk_ready "$app_log"
tk_wait '#{mouse_any_flag}' 1 "$right"
# SGR coordinates are 1-based client columns and rows.
col=$(( $(ti display-message -p -t "$right" '#{pane_left}') + 4 ))
click() { tk_raw "\\e[<${1:-0};$col;3M\\e[<${1:-0};$col;3m"; }

# Each gesture starts after tmux's double-click window (300 ms), so it is a
# fresh click rather than the second half of a double-click.
focus_left() {
    sleep 0.4
    ti select-pane -t test.1
    tk_wait '#{pane_active}' 0 "$right"
}

# Inactive: the click focuses the pane and nothing reaches the app.
focus_left
click
tk_wait '#{pane_active}' 1 "$right"
tk_raw x
tk_until grep -q x "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" x "a focusing click reached the app"

# Inactive, then dragged: still nothing.
focus_left
tk_raw "\\e[<0;$col;3M\\e[<32;$((col + 3));3M\\e[<0;$((col + 3));3m"
tk_wait '#{pane_active}' 1 "$right"
tk_raw y
tk_until grep -q y "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" xy "a focusing drag reached the app"

# Active: the click goes to the app, press and release.
: > "$app_log"
sleep 0.4
click
tk_until grep -q 'm' "$app_log" || fail "a click on the active pane never reached the app"
[[ "$(tk_input "$app_log")" == '^[[<0;'*M'^[[<0;'*m ]] || fail "click on the active pane: $(tk_input "$app_log")"

# Ctrl+click is the app's, not tmux's swap-with-marked-pane.
: > "$app_log"
ti select-pane -t test.1 -m
sleep 0.4
click 16
tk_until grep -q 'm' "$app_log" || fail "Ctrl+click never reached the app"
[[ "$(tk_input "$app_log")" == '^[[<16;'*M'^[[<16;'*m ]] || fail "Ctrl+click: $(tk_input "$app_log")"
assert_eq "$(ti display-message -p -t "$right" '#{pane_index}')" 2 "Ctrl+click swapped panes"

printf 'tmux-mouse: ok\n'
