#!/bin/bash
# Review (ScrollLock, prefix+v): per-program dispatch, Claude's transcript dump
# into copy-mode and back, the review key table, and the nvim popup.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

REVIEW='\e[15;2~'
PREFIX='\001'

tk_start
history_count() { ti capture-pane -p -S - -E - -t "$1" | grep -c -- "$2" || true; }

# Leaving copy-mode in a Claude review sends Esc to that pane even when it is
# not the active one: the hook's formats and target are the pane that changed.
left=$(ti display-message -p -t test '#{pane_id}')
hook_log="$TEST_ROOT/hook.log"
right=$(ti split-window -h -t test -P -F '#{pane_id}' "$(tk_stub claude "$hook_log")")
tk_ready "$hook_log"
ti copy-mode -t "$right"
ti set -p -t "$right" @review claude
ti select-pane -t "$left"
ti send -X -t "$right" cancel
tk_until grep -q $'\e' "$hook_log" || fail "leaving review did not send Esc to the Claude pane"
assert_eq "$(ti show -pqv -t "$right" @review)" "" "@review survived leaving review"
ti kill-pane -t "$right"

# Codex opens its pager, OpenCode its editor view; a shell gets copy-mode.
codex_log="$TEST_ROOT/codex.log"
ti new-window -t test "$(tk_stub codex "$codex_log" --alt)"
tk_ready "$codex_log"
tk_wait '#{pane_current_command}' codex
tk_raw "$REVIEW"
tk_until grep -q $'\x14' "$codex_log" || fail "Codex got no Ctrl+T"
tk_raw "$REVIEW"
tk_expect '^T^T' "ScrollLock again closes Codex's pager" tk_input "$codex_log"
tk_wait '#{pane_in_mode}' 0

opencode_log="$TEST_ROOT/opencode.log"
ti new-window -t test "$(tk_stub opencode "$opencode_log" --alt)"
tk_ready "$opencode_log"
tk_wait '#{pane_current_command}' opencode
tk_raw "$REVIEW"
tk_expect '^Xx' "OpenCode review" tk_input "$opencode_log"

shell=$(ti new-window -t test -P -F '#{pane_id}' 'seq 1 100; exec sleep 3600')
tk_until tk_screen_has 100 "$shell" || fail "fixture text never appeared"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 0 "$shell"
tk_raw "${PREFIX}v"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$shell"

# Claude: the transcript lands in history once per review, copy-mode opens at
# the bottom, and leaving returns Claude to fullscreen.
claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$claude_log" --claude dump)")
tk_ready "$claude_log"
tk_wait '#{alternate_on}' 1 "$claude"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$claude"
assert_eq "$(ti show -pqv -t "$claude" @review)" claude "@review during a Claude review"
tk_wait '#{scroll_position}' 0 "$claude"
assert_eq "$(history_count "$claude" 'first question')" 1 "transcript copies after one review"

# Key table: Ctrl+E jumps to the previous prompt, E starts a selection, D no
# longer copies to the end of the line.
tk_raw '\005'
tk_wait '#{m:❯ third question*,#{copy_cursor_line}}' 1 "$claude"
tk_raw '\005'
tk_wait '#{m:❯ second question*,#{copy_cursor_line}}' 1 "$claude"
tk_raw '\004'
tk_wait '#{m:❯ third question*,#{copy_cursor_line}}' 1 "$claude"
tk_raw E
tk_wait '#{selection_present}' 1 "$claude"
tk_raw E
printf 'before' | ti load-buffer -
tk_raw D
tk_wait '#{m:❯ second question*,#{copy_cursor_line}}' 0 "$claude"
tk_wait '#{selection_present}' 1 "$claude"
assert_eq "$(ti show-buffer)" before "D copied in review"
tk_esc
tk_wait '#{selection_present}' 0 "$claude"
tk_wait '#{pane_in_mode}' 1 "$claude"

tk_raw q
tk_wait '#{pane_in_mode}' 0 "$claude"
tk_wait '#{alternate_on}' 1 "$claude"
assert_eq "$(ti show -pqv -t "$claude" @review)" "" "@review after leaving"
[[ "$(tail -c 1 "$claude_log")" == $'\e' ]] || fail "leaving review did not send Esc last: $(tk_input "$claude_log")"

tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$claude"
assert_eq "$(history_count "$claude" 'first question')" 1 "transcript copies after two reviews"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 0 "$claude"
tk_wait '#{alternate_on}' 1 "$claude"

# A Claude that never dumps: the wait times out, Claude gets Esc, no review.
stuck_log="$TEST_ROOT/stuck.log"
stuck=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$stuck_log" --claude never)")
tk_ready "$stuck_log"
tk_wait '#{alternate_on}' 1 "$stuck"
ti set -g @review-timeout 1
tk_raw "$REVIEW"
tk_until grep -q $'\e$' "$stuck_log" || fail "timed-out review sent no Esc"
tk_contains "did not load" tk_last_message || fail "no timeout message: $(tk_last_message)"
assert_eq "$(ti display-message -p -t "$stuck" '#{pane_in_mode}')" 0 "timed-out review entered copy-mode"
assert_eq "$(ti show -pqv -t "$stuck" @review)" "" "@review after a timeout"

# `o` opens the history read-only in nvim, at the line being viewed, from a
# private temporary file that is gone afterwards.
nvim_log="$TEST_ROOT/nvim.log"
cat > "$TEST_ROOT/bin/nvim" <<EOF
#!/bin/bash
file=\${@: -1}
{
    printf 'args=%s\n' "\$*"
    printf 'review=%s\n' "\$NVIM_REVIEW"
    printf 'mode=%s\n' "\$(stat -c %a "\$file")"
    printf 'line=%s\n' "\$(sed -n "\${2#+}p" "\$file")"
} > "$nvim_log"
EOF
chmod +x "$TEST_ROOT/bin/nvim"
ti select-window -t "$(ti display-message -p -t "$shell" '#{window_id}')"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$shell"
ti send -X -t "$shell" search-backward '^42'
tk_wait '#{copy_cursor_line}' 42 "$shell"
tk_raw o
tk_until test -s "$nvim_log" || fail "o did not open nvim"
grep -q '^args=-R +[0-9]* -- ' "$nvim_log" || fail "nvim arguments: $(cat "$nvim_log")"
grep -qx 'review=1' "$nvim_log" || fail "NVIM_REVIEW not set: $(cat "$nvim_log")"
grep -qx 'mode=600' "$nvim_log" || fail "history file mode: $(cat "$nvim_log")"
grep -qx 'line=42' "$nvim_log" || fail "nvim did not open at the viewed line: $(cat "$nvim_log")"
tk_wait '#{pane_in_mode}' 1 "$shell"
no_history_files() { ! compgen -G "$TMPDIR/tmux-review.*" >/dev/null; }
tk_until no_history_files || fail "history file left behind"

printf 'tmux-review: ok\n'
