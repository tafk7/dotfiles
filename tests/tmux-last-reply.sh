#!/bin/bash
# prefix+y copies the last agent reply: Claude's from its session file into the
# tmux buffer (and so the clipboard), Codex's and OpenCode's by their own keys.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

COPY_REPLY='\001y'

tk_start

# Claude: the last main-thread message with text, all of its text blocks; not a
# subagent's (sidechain) message, not the thinking or tool calls after it.
config="$TEST_ROOT/claude-config"
claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -e "CLAUDE_CONFIG_DIR=$config" -P -F '#{pane_id}' "$(tk_stub claude "$claude_log" --alt)")
tk_ready "$claude_log"
pid=$(ti display-message -p -t "$claude" '#{pane_pid}')
mkdir -p "$config/sessions" "$config/projects/-work"
printf '{"pid":%s,"sessionId":"s1"}\n' "$pid" > "$config/sessions/$pid.json"
python3 - "$config/projects/-work/s1.jsonl" <<'PY'
import json, sys
def assistant(id, *blocks, sidechain=False):
    return {"type": "assistant", "isSidechain": sidechain, "message": {"id": id, "content": list(blocks)}}
text = lambda t: {"type": "text", "text": t}
entries = [
    assistant("m1", text("an older reply")),
    {"type": "user", "message": {"content": "next question"}},
    assistant("m2", {"type": "thinking", "thinking": "hmm"}),
    assistant("m2", text("first part")),
    assistant("m2", text("second part")),
    assistant("m3", {"type": "tool_use", "name": "Bash"}),
    assistant("m4", text("a subagent's reply"), sidechain=True),
]
with open(sys.argv[1], "w") as out:
    out.write("".join(json.dumps(e) + "\n" for e in entries))
PY
tk_mark
tk_raw "$COPY_REPLY"
tk_expect $'first part\n\nsecond part' "Claude's last reply in the buffer" ti show-buffer
tk_expect $'first part\n\nsecond part' "Claude's last reply on the clipboard" tk_osc52
assert_eq "$(tk_input "$claude_log")" "" "copying the reply typed into Claude"

# Shift+Copy is the same command.
printf 'other' | ti load-buffer -
tk_raw '\e[2;6~'
tk_expect $'first part\n\nsecond part' "Shift+Copy copies the last reply" ti show-buffer

# Codex and OpenCode copy with their own keys.
codex_log="$TEST_ROOT/codex.log"
ti new-window -t test "$(tk_stub codex "$codex_log")"
tk_ready "$codex_log"
tk_wait '#{pane_current_command}' codex
tk_raw "$COPY_REPLY"
tk_expect '^O' "Codex copy key" tk_input "$codex_log"

opencode_log="$TEST_ROOT/opencode.log"
ti new-window -t test "$(tk_stub opencode "$opencode_log")"
tk_ready "$opencode_log"
tk_wait '#{pane_current_command}' opencode
tk_raw "$COPY_REPLY"
tk_expect '^Xy' "OpenCode copy key" tk_input "$opencode_log"

# Anywhere else: a message, nothing typed.
app_log="$TEST_ROOT/app.log"
ti new-window -t test "$(tk_stub app "$app_log")"
tk_ready "$app_log"
tk_wait '#{pane_current_command}' app
tk_raw "$COPY_REPLY"
tk_until tk_contains "no agent" tk_last_message || fail "no message outside an agent: $(tk_last_message)"
assert_eq "$(tk_input "$app_log")" "" "prefix+y typed into a plain pane"

printf 'tmux-last-reply: ok\n'
