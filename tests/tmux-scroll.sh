#!/bin/bash
# Shift+PgUp / Shift+PgDn scroll a few lines in every pane (bin/tmux-scroll): a
# shell enters copy-mode that many lines up and leaves it at the bottom;
# copy-mode moves; Claude, Codex, and OpenCode get as many mouse-wheel events
# as make the lines at their own step; a compose pane scrolls its agent; other
# apps get the key itself; @scroll-lines sets the step.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

S_PGUP='\e[5;2~'
S_PGDN='\e[6;2~'

tk_start

# A shell: copy-mode three lines up, then six; down returns, and leaves
# copy-mode at the bottom; down there again sends nothing.
shell_log="$TEST_ROOT/shell.log"
shell=$(ti new-window -t test -P -F '#{pane_id}' "seq 1 200; $(tk_stub shell "$shell_log")")
tk_ready "$shell_log"
tk_raw "$S_PGUP"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_wait '#{scroll_position}' 3 "$shell"
tk_raw "$S_PGUP"
tk_wait '#{scroll_position}' 6 "$shell"
tk_raw "$S_PGDN"
tk_wait '#{scroll_position}' 3 "$shell"
tk_raw "$S_PGDN"
tk_wait '#{pane_in_mode}' 0 "$shell"
tk_raw "${S_PGDN}x"
tk_until grep -q x "$shell_log" || fail "shell stub got no input"
assert_eq "$(tk_input "$shell_log")" x "Shift+PgDn at a shell's bottom"

# wheel PANE BUTTON COUNT: the SGR wheel events tmux-scroll sends PANE, as the
# stub logs them: a third of the way down, column 10.
wheel() {
    local y i out=''
    y=$(($(ti display-message -p -t "$1" '#{pane_height}') / 3))
    for ((i = 0; i < $3; i++)); do out+="^[[<$2;10;${y}M"; done
    printf '%s' "$out"
}

# The agents: Claude and Codex scroll a line per wheel event, OpenCode three.
# Claude at its bottom takes three more to let go of it.
declare -A events=([claude]=3 [codex]=3 [opencode]=1)
declare -A pinned=([claude]=3 [codex]=0 [opencode]=0)
declare -A agent_pane
for agent in claude codex opencode; do
    log="$TEST_ROOT/$agent.log"
    pane=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub "$agent" "$log" --alt --mouse --paste)")
    agent_pane[$agent]=$pane
    tk_ready "$log"
    tk_wait '#{mouse_sgr_flag}' 1 "$pane"
    tk_raw "$S_PGUP"
    tk_expect "$(wheel "$pane" 64 $((events[$agent] + pinned[$agent])))" "Shift+PgUp in $agent" tk_input "$log"
    : > "$log"
    tk_raw "$S_PGDN"
    tk_expect "$(wheel "$pane" 65 "${events[$agent]}")" "Shift+PgDn in $agent" tk_input "$log"
    : > "$log"
done

# A compose pane scrolls its agent and gets nothing itself.
claude=${agent_pane[claude]}
compose_log="$TEST_ROOT/compose.log"
ti select-window -t "$claude"
compose=$(ti split-window -v -t "$claude" -P -F '#{pane_id}' "$(tk_stub nvim "$compose_log" --alt --mouse)")
ti set -p -t "$compose" @compose_target "$claude"
tk_ready "$compose_log"
tk_wait '#{pane_id}' "$compose"
tk_raw "${S_PGUP}x"
tk_expect "$(wheel "$claude" 64 6)" "Shift+PgUp from a compose pane" tk_input "$TEST_ROOT/claude.log"
tk_until grep -q x "$compose_log" || fail "compose stub got no input"
assert_eq "$(tk_input "$compose_log")" x "the compose pane's own input"
: > "$TEST_ROOT/claude.log"

# A Claude scrolled up shows "Jump to bottom" and gets just the three.
loose_log="$TEST_ROOT/loose.log"
loose=$(ti new-window -t test -P -F '#{pane_id}' \
    "printf 'Jump to bottom (ctrl+End)\\n'; $(tk_stub claude "$loose_log" --mouse --paste)")
tk_ready "$loose_log"
tk_wait '#{mouse_sgr_flag}' 1 "$loose"
tk_raw "$S_PGUP"
tk_expect "$(wheel "$loose" 64 3)" "Shift+PgUp in a Claude scrolled up" tk_input "$loose_log"
ti kill-window -t "$loose"

# Any other app gets the key, mouse-aware or not.
for flags in "--alt --mouse" "--alt"; do
    log="$TEST_ROOT/app.log"
    : > "$log"
    # shellcheck disable=SC2086  # one argument per flag
    ti new-window -t test "$(tk_stub app "$log" $flags)"
    tk_ready "$log"
    tk_wait '#{pane_current_command}' app
    tk_raw "$S_PGUP$S_PGDN"
    tk_expect '^[[5;2~^[[6;2~' "Shift+PgUp/PgDn in an app ($flags)" tk_input "$log"
    ti kill-window
done

# pi scrolls a line a press (configs/ai/pi/keybindings.json), so it gets the
# key three times.
log="$TEST_ROOT/pi.log"
ti new-window -t test "$(tk_stub pi "$log" --alt --mouse)"
tk_ready "$log"
tk_wait '#{pane_current_command}' pi
tk_raw "$S_PGUP$S_PGDN"
tk_expect '^[[5;2~^[[5;2~^[[5;2~^[[6;2~^[[6;2~^[[6;2~' "Shift+PgUp/PgDn in pi" tk_input "$log"
ti kill-window

# @scroll-lines sets the step: six lines are six Claude events (and the three
# at its bottom), two OpenCode ones, and six lines of a shell's history.
ti set -g @scroll-lines 6
ti select-window -t "$claude"
ti select-pane -t "$claude"
tk_raw "$S_PGUP"
tk_expect "$(wheel "$claude" 64 9)" "six lines in Claude" tk_input "$TEST_ROOT/claude.log"
ti select-window -t "${agent_pane[opencode]}"
tk_raw "$S_PGUP"
tk_expect "$(wheel "${agent_pane[opencode]}" 64 2)" "six lines in OpenCode" tk_input "$TEST_ROOT/opencode.log"
ti select-window -t "$shell"
tk_raw "$S_PGUP"
tk_wait '#{scroll_position}' 6 "$shell"

printf 'tmux-scroll: ok\n'
