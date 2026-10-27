#!/bin/bash
# Review (ScrollLock, prefix+f): a shell's history in place; an agent's
# conversation, as the agent exports it, in a review pane zoomed over the agent;
# the review key table; prefix+/ (review and search) and prefix+o and o (the
# nvim popup).
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

REVIEW='\e[15;2~'
PREFIX='\001'

tk_start
history_count() { ti capture-pane -p -S - -E - -t "$1" | grep -c -- "$2" || true; }
no_review_files() { ! compgen -G "$TMPDIR/tmux-review.*" >/dev/null; }
no_claude_files() { ! compgen -G "$TMPDIR/cc-transcript-*" >/dev/null; }

# await_review TARGET: a review pane over TARGET is active, zoomed, and in
# copy-mode; prints its id.
await_review() {
    tk_expect "$1 1 1" "review pane over $1" ti display-message -p '#{@review-pane} #{pane_in_mode} #{window_zoomed_flag}'
    ti display-message -p '#{pane_id}'
}

# await_closed TARGET [ZOOMED]: the review pane is gone and TARGET has focus.
review_panes() { ti list-panes -a -F '#{@review-pane}' | grep -c . || true; }
await_closed() {
    tk_expect "$1 ${2:-0}" "focus after review" ti display-message -p '#{pane_id} #{window_zoomed_flag}'
    tk_expect 0 "review panes left" review_panes
}

# The line under the copy-mode cursor, counted from the top of history.
cursor_row() { ti display-message -p -t "$1" '#{e|+:#{e|-:#{history_size},#{scroll_position}},#{copy_cursor_y}}'; }

# A review pane that leaves copy-mode is removed even when it isn't the active
# pane: the hook's formats and target are the pane that changed.
left=$(ti display-message -p -t test '#{pane_id}')
right=$(ti split-window -h -t test -P -F '#{pane_id}' 'exec sleep 3600')
ti set -p -t "$right" @review-pane "$left"
ti copy-mode -t "$right"
ti select-pane -t "$left"
ti send -X -t "$right" cancel
tk_until tk_lacks "$right" ti list-panes -t test -F '#{pane_id}' || fail "the review pane survived leaving copy-mode"

# The popup's nvim records how it was started and what it was shown.
nvim_log="$TEST_ROOT/nvim.log"
cat > "$TEST_ROOT/bin/nvim" <<EOF
#!/bin/bash
file=\${@: -1}
{
    printf 'args=%s\n' "\$*"
    printf 'review=%s\n' "\$NVIM_REVIEW"
    printf 'prompt=%s\n' "\$NVIM_REVIEW_PROMPT"
    printf 'mode=%s\n' "\$(stat -c %a "\$file")"
    printf 'first=%s\n' "\$(head -n 1 "\$file")"
    printf 'line=%s\n' "\$(sed -n "\${2#+}p" "\$file")"
} > "$nvim_log"
EOF
chmod +x "$TEST_ROOT/bin/nvim"

# A shell is reviewed in place.
shell=$(ti new-window -t test -P -F '#{pane_id}' 'seq 1 100; exec sleep 3600')
tk_until tk_screen_has 100 "$shell" || fail "fixture text never appeared"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$shell"
assert_eq "$(ti display-message -p '#{pane_id} #{window_zoomed_flag}')" "$shell 0" "shell review left its pane"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 0 "$shell"
tk_raw "${PREFIX}f"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$shell"

# prefix+/ reviews and searches upward at once.
tk_raw "${PREFIX}/"
tk_wait '#{pane_in_mode}' 1 "$shell"
tk_raw '42\r'
tk_wait '#{copy_cursor_line}' 42 "$shell"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$shell"

# In a shell, Ctrl+E/D jump between the OSC 133 prompt marks. Without
# Starship on PATH the prompt is one line, so the mark is on the command's line.
prompt_shell=$(ti new-window -t test -P -F '#{pane_id}' \
    "env -u SSH_CONNECTION PATH=$(printf '%q' "$TEST_ROOT/bin:$TEST_SYSTEM_PATH") bash --rcfile $(printf '%q' "$DOTFILES_DIR/entry/bash.sh") -i")
tk_until tk_screen_has '$' "$prompt_shell" || fail "the shell prompt never appeared"
ti send-keys -t "$prompt_shell" 'echo first-command' Enter 'echo second-command' Enter
tk_until tk_screen_has 'second-command' "$prompt_shell" || fail "commands never ran"
tk_raw "$REVIEW"
tk_wait '#{pane_in_mode}' 1 "$prompt_shell"
tk_raw '\005'
tk_wait '#{m:*echo second-command*,#{copy_cursor_line}}' 1 "$prompt_shell"
tk_raw '\005'
tk_wait '#{m:*echo first-command*,#{copy_cursor_line}}' 1 "$prompt_shell"
tk_raw '\004'
tk_wait '#{m:*echo second-command*,#{copy_cursor_line}}' 1 "$prompt_shell"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$prompt_shell"

# Claude hands its transcript (Ctrl+O v) to compose-editor, which moves it to
# review; Ctrl+O then closes Claude's transcript view. Nothing else is typed.
editor="VISUAL=$DOTFILES_DIR/bin/compose-editor"
claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -e "$editor" -P -F '#{pane_id}' "$(tk_stub claude "$claude_log" --claude transcript)")
tk_ready "$claude_log"
tk_wait '#{alternate_on}' 1 "$claude"

# prefix+v is plain copy-mode on the live screen: Claude is left alone.
tk_raw "${PREFIX}v"
tk_wait '#{pane_in_mode}' 1 "$claude"
tk_screen_has 'stub on the alternate screen' "$claude" || fail "prefix+v left the live screen"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$claude"
sleep 0.3
assert_eq "$(tk_input "$claude_log")" "" "prefix+v sent keys to Claude"

tk_raw "${PREFIX}f"
review=$(await_review "$claude")
tk_expect '^Ov^O' "keys sent to Claude for review" tk_input "$claude_log"
assert_eq "$(history_count "$review" 'first question')" 1 "transcript copies in the review pane"
assert_eq "$(ti show -pqv -t "$claude" @review-file)" "" "@review-file after the hand-over"
tk_until no_claude_files || fail "Claude's transcript file was left behind"
tk_until no_review_files || fail "review files left behind"
tk_until tk_screen_has 'stub on the alternate screen' "$claude" || fail "Claude stayed in its transcript view"

# Key table: Ctrl+E jumps to the previous prompt (the review pane marks them),
# E starts a selection, D no longer copies to the end of the line.
tk_raw '\005'
tk_wait '#{m:❯ third question*,#{copy_cursor_line}}' 1 "$review"
tk_raw '\005'
tk_wait '#{m:❯ second question*,#{copy_cursor_line}}' 1 "$review"
tk_raw '\004'
tk_wait '#{m:❯ third question*,#{copy_cursor_line}}' 1 "$review"
tk_raw E
tk_wait '#{selection_present}' 1 "$review"
tk_raw E
printf 'before' | ti load-buffer -
tk_raw D
tk_wait '#{m:❯ second question*,#{copy_cursor_line}}' 0 "$review"
tk_wait '#{selection_present}' 1 "$review"
assert_eq "$(ti show-buffer)" before "D copied in review"
tk_esc
tk_wait '#{selection_present}' 0 "$review"
tk_wait '#{pane_in_mode}' 1 "$review"

# Home and End stay on the line.
row=$(ti display-message -p -t "$review" '#{copy_cursor_y}')
tk_raw '\e[F'
tk_wait '#{e|>:#{copy_cursor_x},5}' 1 "$review"
tk_raw '\e[H'
tk_wait '#{copy_cursor_x}' 0 "$review"
assert_eq "$(ti display-message -p -t "$review" '#{copy_cursor_y}')" "$row" "Home/End left the line"

# y copies and leaves; the window is Claude's again.
tk_raw '\005'
tk_wait '#{m:❯ second question*,#{copy_cursor_line}}' 1 "$review"
tk_raw 'v\e[F'
tk_raw y
await_closed "$claude"
assert_eq "$(ti show-buffer)" "❯ second question" "y in review"
assert_eq "$(tk_input "$claude_log")" '^Ov^O' "keys sent to Claude after review"

# A second review shows one copy; the review key leaves it; a zoomed window
# stays zoomed, with its other panes as they were.
other=$(ti split-window -d -t "$claude" -P -F '#{pane_id}' 'exec sleep 3600')
ti resize-pane -Z -t "$claude"
tk_raw "$REVIEW"
review=$(await_review "$claude")
assert_eq "$(history_count "$review" 'first question')" 1 "transcript copies after two reviews"
tk_raw "$REVIEW"
await_closed "$claude" 1
ti kill-pane -t "$other"

# With Claude's transcript view already open, review sends only v and leaves the
# view open.
: > "$claude_log"
tk_raw '\017'
tk_until tk_screen_has 'Showing detailed transcript' "$claude" || fail "the stub's transcript view never opened"
tk_raw "$REVIEW"
review=$(await_review "$claude")
tk_raw q
await_closed "$claude"
assert_eq "$(tk_input "$claude_log")" '^Ov' "keys sent to Claude with its transcript view open"
tk_raw '\017'
tk_until tk_screen_has 'stub on the alternate screen' "$claude" || fail "the stub's transcript view never closed"

# prefix+o opens the conversation in the nvim popup, from a private file that
# is gone afterwards.
: > "$claude_log"
tk_raw "${PREFIX}o"
tk_until test -s "$nvim_log" || fail "prefix+o did not open nvim"
grep -q '^args=-R + -- ' "$nvim_log" || fail "nvim arguments: $(cat "$nvim_log")"
grep -qx 'review=1' "$nvim_log" || fail "NVIM_REVIEW not set: $(cat "$nvim_log")"
grep -qx 'prompt=^❯ ' "$nvim_log" || fail "NVIM_REVIEW_PROMPT: $(cat "$nvim_log")"
grep -qx 'mode=600' "$nvim_log" || fail "transcript file mode: $(cat "$nvim_log")"
grep -qx 'first=❯ first question' "$nvim_log" || fail "popup did not show the transcript: $(cat "$nvim_log")"
tk_expect '^Ov^O' "keys sent to Claude for prefix+o" tk_input "$claude_log"
tk_until no_review_files || fail "transcript file left behind"
: > "$nvim_log"

# prefix+/ in Claude: review, then the search prompt.
tk_raw "${PREFIX}/"
review=$(await_review "$claude")
tk_until tk_contains '(search up)' tk_client_screen || fail "no search prompt"
tk_raw 'first answer\r'
tk_wait '#{m:● first answer*,#{copy_cursor_line}}' 1 "$review"

# o in a review pane opens what it shows, at the line being viewed.
tk_raw o
tk_until test -s "$nvim_log" || fail "o did not open nvim"
grep -qx 'line=● first answer' "$nvim_log" || fail "nvim did not open at the viewed line: $(cat "$nvim_log")"
grep -qx 'prompt=^❯ ' "$nvim_log" || fail "NVIM_REVIEW_PROMPT from a review pane: $(cat "$nvim_log")"
tk_wait '#{pane_in_mode}' 1 "$review"
tk_raw q
await_closed "$claude"
: > "$nvim_log"

# With another VISUAL, or a compose-editor from before the hand-over, Ctrl+O v
# would stop Claude for an editor in its place, so review opens Claude's own
# transcript view instead.
mkdir -p "$TEST_ROOT/old"
printf '#!/bin/sh\nexec vi "$@"\n' > "$TEST_ROOT/old/compose-editor"
chmod +x "$TEST_ROOT/old/compose-editor"
plain_log="$TEST_ROOT/claude-plain.log"
plain=$(ti new-window -t test -e "VISUAL=$TEST_ROOT/old/compose-editor" -P -F '#{pane_id}' \
    "$(tk_stub claude "$plain_log" --claude transcript)")
tk_ready "$plain_log"
tk_wait '#{alternate_on}' 1 "$plain"
tk_raw "$REVIEW"
tk_until tk_contains "transcript view is open" tk_last_message || fail "no message without compose-editor: $(tk_last_message)"
assert_eq "$(tk_input "$plain_log")" '^O' "keys sent to Claude without compose-editor"
assert_eq "$(ti display-message -p '#{pane_id} #{pane_in_mode}')" "$plain 0" "review without compose-editor"

# A Claude that never hands over: a message, nothing more typed, no review.
stuck_log="$TEST_ROOT/stuck.log"
stuck=$(ti new-window -t test -e "$editor" -P -F '#{pane_id}' "$(tk_stub claude "$stuck_log" --claude never)")
tk_ready "$stuck_log"
tk_wait '#{alternate_on}' 1 "$stuck"
ti set -g @review-timeout 1
tk_raw "$REVIEW"
tk_until tk_contains "did not hand over" tk_last_message || fail "no timeout message: $(tk_last_message)"
assert_eq "$(tk_input "$stuck_log")" '^Ov' "keys sent to a Claude that never hands over"
assert_eq "$(ti display-message -p '#{pane_id} #{pane_in_mode}')" "$stuck 0" "timed-out review"
assert_eq "$(ti show -pqv -t "$stuck" @review-file)" "" "@review-file after a timeout"
tk_until no_review_files || fail "review files left after a timeout"
ti set -gu @review-timeout

# Codex: its session file as Markdown, chosen by the thread id in the pane
# title (cut short, as Codex writes it), over a newer session in the same
# directory. Nothing is typed into Codex.
codex_home="$TEST_ROOT/codex-home"
sessions="$codex_home/sessions/2026/10/27"
mkdir -p "$sessions" "$TEST_ROOT/codex-project"
python3 - "$sessions" "$TEST_ROOT/codex-project" <<'PY'
import json, os, sys
sessions, cwd = sys.argv[1:]
def rollout(name, thread, items, mtime):
    path = os.path.join(sessions, f"rollout-2026-10-27T06-00-00-{thread}.jsonl")
    records = [{"type": "session_meta", "payload": {"id": thread, "cwd": cwd}},
               {"type": "response_item", "payload": {"type": "message", "role": "user",
                "content": [{"type": "input_text", "text": "<environment_context>"}]}}]
    records += [{"type": "event_msg", "payload": {"type": "item_completed", "item": item}} for item in items]
    with open(path, "w") as out:
        out.write("".join(json.dumps(r) + "\n" for r in records))
    os.utime(path, (mtime, mtime))
user = lambda t: {"type": "UserMessage", "content": [{"type": "text", "text": t}]}
agent = lambda t: {"type": "AgentMessage", "content": [{"type": "Text", "text": t}]}
rollout("target", "01a17c07-e4d7-7a91-a0c6-65da4b2f9c11", [
    user("first codex question"),
    {"type": "Reasoning", "summary_text": ["secret thoughts"]},
    agent("an answer"),
    {"type": "CommandExecution", "command": ["/bin/bash", "-lc", "printf 'alpha\\n'"], "aggregated_output": "alpha\n"},
    {"type": "FileChange", "changes": {"/work/notes.txt": {"type": "update", "unified_diff": "@@ -1 +1 @@\n-old line\n+new line\n"}}},
    user("second codex question"),
    agent("final answer, then a long line: " + " ".join(f"word{n}" for n in range(40))),
], 1000)
rollout("newer", "01a17c08-0000-7000-8000-000000000000", [user("other thread question"), agent("other answer")], 2000)
PY
codex_log="$TEST_ROOT/codex.log"
codex=$(ti new-window -t test -c "$TEST_ROOT/codex-project" -e "CODEX_HOME=$codex_home" -P -F '#{pane_id}' \
    "$(tk_stub codex "$codex_log" --alt --title '01a17c07-e4d7-7a91-a0c6-65da4... | a thread | project')")
tk_ready "$codex_log"
tk_wait '#{pane_current_command}' codex
tk_raw "$REVIEW"
review=$(await_review "$codex")
text=$(ti capture-pane -p -J -S - -E - -t "$review")
[[ "$text" == "# Codex session 01a17c07-e4d7-7a91-a0c6-65da4"* ]] || fail "Codex review heading: $(head -n 3 <<<"$text")"
for want in 'first codex question' 'an answer' "\$ printf 'alpha\\n'" 'Update `/work/notes.txt`' '+new line' 'final answer'; do
    [[ "$text" == *"$want"* ]] || fail "Codex review lacks '$want': $text"
done
for unwanted in 'secret thoughts' 'environment_context' 'other thread'; do
    [[ "$text" != *"$unwanted"* ]] || fail "Codex review shows '$unwanted'"
done
tk_raw '\005'
tk_wait '#{copy_cursor_line}' '## User' "$review"
second=$(cursor_row "$review")
tk_raw '\005'
tk_until test "$(cursor_row "$review")" -lt "$second" || fail "Ctrl+E did not reach the first Codex prompt"
tk_wait '#{copy_cursor_line}' '## User' "$review"

# A line wider than the pane wraps on screen and copies whole. (tmux 3.4's
# search misses text on wrapped lines, so the cursor walks there from the
# prompt before it.)
ti send -X -t "$review" search-backward 'second codex question'
ti send -X -t "$review" -N 4 cursor-down
tk_wait '#{m:final answer*,#{copy_cursor_line}}' 1 "$review"
ti send -X -t "$review" select-line
tk_raw y
await_closed "$codex"
assert_eq "$(ti show-buffer)" "final answer, then a long line: $(printf 'word%s ' {0..39} | sed 's/ $//')" "copying a wrapped line"
assert_eq "$(tk_input "$codex_log")" "" "review typed into Codex"

# Without a thread id in the title: the newest session in the directory, and
# the heading says so.
untitled_log="$TEST_ROOT/codex-untitled.log"
untitled=$(ti new-window -t test -c "$TEST_ROOT/codex-project" -e "CODEX_HOME=$codex_home" -P -F '#{pane_id}' \
    "$(tk_stub codex "$untitled_log" --alt)")
tk_ready "$untitled_log"
tk_wait '#{pane_current_command}' codex
tk_raw "$REVIEW"
review=$(await_review "$untitled")
tk_contains 'newest session in this directory' ti capture-pane -p -S - -t "$review" || fail "untitled Codex review heading"
tk_contains 'other thread question' ti capture-pane -p -S - -t "$review" || fail "untitled Codex review shows another session"
tk_raw q
await_closed "$untitled"

# OpenCode: its export dialog is driven to Export, the notice is closed, and
# the exported file moves into the review pane.
opencode_log="$TEST_ROOT/opencode.log"
mkdir -p "$TEST_ROOT/project"
opencode=$(ti new-window -t test -c "$TEST_ROOT/project" -P -F '#{pane_id}' "$(tk_stub opencode "$opencode_log" --opencode)")
tk_ready "$opencode_log"
tk_wait '#{pane_current_command}' opencode
tk_raw "$REVIEW"
review=$(await_review "$opencode")
assert_eq "$(tk_input "$opencode_log")" '^Xx^[[Z^M^[' "OpenCode review keys"
assert_eq "$(history_count "$review" 'first question')" 1 "OpenCode export in the review pane"
[[ ! -e "$TMPDIR/session-stub.md" ]] || fail "the export was left behind"
tk_until no_review_files || fail "export file left behind"
tk_raw q
await_closed "$opencode"

# o in a shell's review opens its history read-only in nvim, at the line being
# viewed, from a private temporary file that is gone afterwards.
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
tk_until no_review_files || fail "history file left behind"
tk_raw q
tk_wait '#{pane_in_mode}' 0 "$shell"

printf 'tmux-review: ok\n'
