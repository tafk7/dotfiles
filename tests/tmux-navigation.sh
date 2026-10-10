#!/bin/bash
# Alt+E/S/D/F and Alt+arrows: pane moves that cross to the facing pane of the
# neighboring window at the outer edge and stop at the ends. PgUp and Ctrl+Home
# browse a shell's history in copy-mode and belong to fullscreen apps.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

PGUP='\e[5~'
CTRL_HOME='\e[1;5H'

tk_start

# Window 1: left | right. Window 2: left | right split top/bottom.
w1_left=$(ti display-message -p -t test '#{pane_id}')
w1_right=$(ti split-window -h -t "$w1_left" -P -F '#{pane_id}' 'exec sleep 3600')
w2_left=$(ti new-window -t test -P -F '#{pane_id}' 'exec sleep 3600')
w2_right_top=$(ti split-window -h -t "$w2_left" -P -F '#{pane_id}' 'exec sleep 3600')
w2_right_bottom=$(ti split-window -v -t "$w2_right_top" -P -F '#{pane_id}' 'exec sleep 3600')

at() {
    ti select-window -t "$(ti display-message -p -t "$1" '#{window_id}')"
    ti select-pane -t "$1"
    tk_wait '#{pane_id}' "$1"
}
lands() { tk_wait '#{pane_id}' "$1"; }

# Horizontal moves inside a window, then across the edge to the facing pane.
at "$w1_left"
tk_raw '\ef'
lands "$w1_right"
tk_raw '\ef'
lands "$w2_left"
tk_raw '\es'
lands "$w1_right"

# The ends stop instead of wrapping.
at "$w1_left"
tk_raw '\es'
sleep 0.2
lands "$w1_left"
tk_contains "first window" tk_last_message || fail "no first-window message: $(tk_last_message)"
at "$w2_right_top"
tk_raw '\ef'
sleep 0.2
lands "$w2_right_top"
tk_contains "last window" tk_last_message || fail "no last-window message: $(tk_last_message)"

# Vertical moves stop at the edge.
at "$w2_right_top"
tk_raw '\ee'
sleep 0.2
lands "$w2_right_top"
tk_raw '\ed'
lands "$w2_right_bottom"
tk_raw '\ed'
sleep 0.2
lands "$w2_right_bottom"

# Alt+arrows are the same moves.
at "$w2_right_bottom"
tk_raw '\e[1;3A'
lands "$w2_right_top"
tk_raw '\e[1;3D'
lands "$w2_left"
tk_raw '\e[1;3D'
lands "$w1_right"
tk_raw '\e[1;3C'
lands "$w2_left"

# PgUp in a shell pane enters copy-mode a page up; inside copy-mode it pages.
shell=$(ti new-window -t test -P -F '#{pane_id}' 'seq 1 200; exec sleep 3600')
tk_until tk_screen_has 200 "$shell" || fail "fixture text never appeared"
tk_raw "$PGUP"
tk_wait '#{pane_in_mode}' 1 "$shell"
first=$(ti display-message -p -t "$shell" '#{scroll_position}')
(( first > 0 )) || fail "PgUp did not scroll up ($first)"
tk_raw "$PGUP"
tk_wait "#{e|>:#{scroll_position},$first}" 1 "$shell"
ti send -X -t "$shell" cancel

# Ctrl+Home enters copy-mode at the top.
tk_raw "$CTRL_HOME"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_wait '#{==:#{scroll_position},#{history_size}}' 1 "$shell"
ti send -X -t "$shell" cancel

# Fullscreen apps get both keys.
app_log="$TEST_ROOT/app.log"
ti new-window -t test "$(tk_stub app "$app_log" --alt)"
tk_ready "$app_log"
tk_wait '#{alternate_on}' 1
tk_raw "${PGUP}${CTRL_HOME}x"
tk_until grep -q x "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" '^[[5~^[[1;5Hx' "PgUp and Ctrl+Home in a fullscreen app"
tk_wait '#{pane_in_mode}' 0

printf 'tmux-navigation: ok\n'
