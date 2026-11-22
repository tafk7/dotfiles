#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
unset DISABLE_AUTO_COMPACT DISABLE_COMPACT STATUSLINE_DUMP SCRIV_DESK
unset CLAUDE_CONFIG_DIR
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
command -v jq >/dev/null || fail 'jq required'

sid=11111111-0000-4000-8000-000000000001
project="$TEST_ROOT/project"
transcript="$TEST_ROOT/transcript.jsonl"
mkdir -p "$project/.claude" "$HOME/.claude" "$TEST_ROOT/desk/.runtime/compact"
key=$(printf '%s' "$sid" | sha256sum); key=${key%% *}
record="$TEST_ROOT/desk/.runtime/compact/$key.json"
export SCRIV_DESK="$TEST_ROOT/desk"
input=$(jq -nc --arg sid "$sid" --arg project "$project" --arg tp "$transcript" '{
    session_id: $sid, transcript_path: $tp,
    model: {id: "claude-sonnet-5-5", display_name: "Sonnet 5.5"},
    workspace: {project_dir: $project, current_dir: $project},
    context_window: {used_percentage: 0, context_window_size: 1000000}}')

render() {
    printf '%s\n' "$input" | bash "$TEST_REPO_ROOT/configs/ai/claude/statusline.sh" \
        2> "$TEST_ROOT/stderr" | sed $'s/\033\\[[0-9;]*m//g'
    [[ ! -s "$TEST_ROOT/stderr" ]] || fail "unexpected stderr: $(cat "$TEST_ROOT/stderr")"
}
marker() {
    local line bar before
    line=$(render); bar=${line%% *}
    [[ "$bar" == *│* ]] || fail "missing marker: $line"
    before=${bar%%│*}
    assert_eq "${#before}" "$1" "$2"
    assert_eq "${#bar}" 20 'bar width'
}
write_record() {
    jq -nc --arg sid "$1" '{session: $sid, harness: "claude", compaction: {
        trigger: 150000, window: 183000, reservation: 33000, source: "seat:primary"},
        compact_pending: {trigger: 450000}, applied_to: "another-session"}' > "$record"
}
command_result() {
    jq -nc --arg sid "$sid" --arg n "$1" '{sessionId: $sid, type: "system",
        subtype: "local_command", commandRun: {command: "autocompact", args: $n},
        content: ("<local-command-stdout>Auto-compact window for Sonnet 5.5 set to "
          + $n + " tokens</local-command-stdout>")}' >> "$transcript"
}

marker 19 'no record or live command: default 967k trigger'
write_record "$sid"
marker 3 'record supplies the applied 150k trigger, ignoring pending tuning'
write_record another-session
marker 19 'a record for another session is ignored'
write_record "$sid"
command_result 383k
marker 7 'live 383k window overrides record: 350k trigger'
command_result 533000
marker 10 'latest live command wins: 500k trigger'

# Assistant quotes, ordinary user prose, queued requests, and failed local
# commands never change the applied native setting.
cat >> "$transcript" <<'JSONL'
{"type":"assistant","message":{"content":"/autocompact 833k"}}
{"type":"user","message":{"content":"please run /autocompact 833k"}}
{"type":"queue-operation","content":"/autocompact 833k"}
{"type":"system","subtype":"local_command","commandRun":{"command":"autocompact","args":"833k"},"content":"CLAUDE_CODE_AUTO_COMPACT_WINDOW is set and takes precedence."}
{"type":"system","subtype":"local_command","commandRun":{"command":"autocompact","args":"nonsense"},"content":"Couldn't parse 'nonsense'"}
{"type":"system","subtype":"local_command","sessionId":"another-session","commandRun":{"command":"autocompact","args":"833k"},"content":"Auto-compact window for Sonnet 5.5 set to 833k tokens"}
JSONL
marker 10 'only applied commands for this session count'
cat >> "$transcript" <<'JSONL'
{"type":"user","message":4}
{"type":"system","subtype":"local_command","commandRun":[],"content":"Auto-compact window for Sonnet 5.5 set to 833k tokens"}
{"type":"system","subtype":"local_command","content":{}}
JSONL
command_result 683k
marker 13 'malformed entry shapes do not hide the latest valid command'
command_result 533000
marker 10 'valid commands remain readable after malformed shapes'

# The observed override survives growing beyond the bounded tail. A torn
# first/last JSON line and a malformed line cannot hide valid entries.
head -c 100000 /dev/zero | tr '\0' x >> "$transcript"
printf '\n{broken}\n' >> "$transcript"
marker 10 'cached override survives leaving the tail'
command_result 283k
printf '{"unfinished":' >> "$transcript"
marker 5 'valid command survives damaged JSONL: 250k trigger'

# Truncation drops the cached live setting.
printf '\n' > "$transcript"
marker 3 'truncated transcript invalidates the override cache'
command_result auto
marker 19 'native reset clears the recorded launch override'

# A smaller model output reservation is used for live windows when recorded.
printf '\n' > "$transcript"
jq '.compaction = {trigger:150000, window:171000, reservation:21000}' "$record" > "$TEST_ROOT/new-record"
mv "$TEST_ROOT/new-record" "$record"
command_result 171k
marker 3 'live window uses the recorded 21k reserve'
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
marker 1 'live window applies the native percent override'
unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE

# Older transcripts carry the command's XML and its local stdout without the
# commandRun metadata. Ordinary content never counts as an executed command.
printf '\n' > "$transcript"
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<command-name>/autocompact</command-name>\n<command-message>autocompact</command-message>\n<command-args>371k</command-args>"}}
{"type":"system","subtype":"local_command","content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to 371k tokens</local-command-stdout>"}
JSONL
marker 7 'legacy command plus applied result: 350k trigger'
command_result 0.271m
marker 5 'decimal native shorthand: 250k trigger'

# Read only 64 KiB from a 110 MB transcript, then reuse its cached state on
# unchanged refreshes. This guard fails any unbounded transcript read by tail.
tail_bin=$(command -v tail)
export STATUSLINE_TAIL_LOG="$TEST_ROOT/tail.log"
printf '#!/bin/bash\n[[ "$1" == -c && "$2" == 65536 ]] || exit 99\nprintf "read\\n" >> "$STATUSLINE_TAIL_LOG"\nexec %q "$@"\n' \
    "$tail_bin" > "$TEST_ROOT/bin/tail"
chmod +x "$TEST_ROOT/bin/tail"
truncate -s 110000000 "$transcript"
printf '\n' >> "$transcript"
command_result 371k
marker 7 'bounded read from a large transcript'
marker 7 'unchanged transcript uses its cache'
assert_eq "$(wc -l < "$STATUSLINE_TAIL_LOG")" 1 'no tail read on unchanged refresh'
rm "$TEST_ROOT/bin/tail"

rm "$record" "$transcript"
printf '{"autoCompactWindow":183000}\n' > "$HOME/.claude/settings.json"
marker 3 'settings window subtracts the 33k reserve'
printf '{"autoCompactWindow":383000}\n' > "$project/.claude/settings.json"
marker 7 'project settings override user settings'
printf '{"modelSettings":{"claude-sonnet":{"autoCompactWindow":583000},"claude-sonnet-5-5":{"autoCompactWindow":233000}}}\n' > "$project/.claude/settings.local.json"
marker 4 'longest matching model setting: 200k trigger'
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=183k
marker 3 'environment window subtracts reserve and beats settings'
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
marker 1 'percent override applies to window minus output reserve: 81.5k'
unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1m
marker 19 'window cap and reserve'
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW
rm "$HOME/.claude/settings.json" "$project/.claude/settings.json" "$project/.claude/settings.local.json"

# The foreground process flag needs the same window-to-trigger conversion.
mkdir -p "$TEST_ROOT/flag"
cat > "$TEST_ROOT/flag/claude" <<'SH'
#!/bin/bash
printf '%s\n' "$STATUSLINE_INPUT" | bash "$STATUSLINE_SCRIPT"
SH
chmod +x "$TEST_ROOT/flag/claude"
line=$(STATUSLINE_INPUT="$input" STATUSLINE_SCRIPT="$TEST_REPO_ROOT/configs/ai/claude/statusline.sh" \
    "$TEST_ROOT/flag/claude" --autocompact 183000 | sed $'s/\033\\[[0-9;]*m//g')
bar=${line%% *}; before=${bar%%│*}
assert_eq "${#before}" 3 'foreground flag: 150k trigger'
command_result 383k
line=$(STATUSLINE_INPUT="$input" STATUSLINE_SCRIPT="$TEST_REPO_ROOT/configs/ai/claude/statusline.sh" \
    "$TEST_ROOT/flag/claude" --autocompact 183000 | sed $'s/\033\\[[0-9;]*m//g')
bar=${line%% *}; before=${bar%%│*}
assert_eq "${#before}" 7 'native live command replaces foreground flag'
rm "$transcript"

# Desk discovery is only a fallback; it requires a [desk] table.
unset SCRIV_DESK
mkdir -p "$project/.runtime/compact"
record="$project/.runtime/compact/$key.json"
write_record "$sid"
printf '[other]\n' > "$project/project.toml"
marker 19 'project.toml without a desk table is ignored'
printf '[desk] # configuration\n' > "$project/project.toml"
marker 3 'nearest project desk fallback'
input=$(printf '%s' "$input" | jq --arg p "$project/nested" '.workspace.project_dir=$p')
mkdir -p "$project/nested"
marker 3 'desk fallback walks ancestors'

printf '{broken}\n' > "$record"
marker 19 'malformed runtime record is ignored'
printf '{"session":"%s","harness":"codex","compaction":{"trigger":150000}}\n' "$sid" > "$record"
marker 19 'another harness is ignored'
printf '{broken}\n' > "$HOME/.claude/settings.json"
marker 19 'malformed settings are ignored'
printf '[1,2,3]\n' > "$record"
marker 19 'non-object runtime is ignored'
printf '{"session":"%s","harness":"claude","compaction":{"trigger":"1;exit","reservation":{}}}\n' "$sid" > "$record"
marker 19 'invalid runtime fields are ignored'
write_record "$sid"
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
marker 3 'record trigger already describes the applied compaction point'
unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE

# Optional state may be missing, unreadable, or unwritable.
printf 'not a directory\n' > "$TEST_ROOT/no-cache"
export XDG_CACHE_HOME="$TEST_ROOT/no-cache"
command_result 383k
marker 7 'unwritable cache does not break live commands'
chmod 000 "$transcript" "$record"
marker 19 'unreadable transcript and record are ignored'
chmod 600 "$transcript" "$record"
export DISABLE_AUTO_COMPACT=1
line=$(render)
[[ "${line%% *}" != *│* ]] || fail 'disabled autocompact still draws a marker'
unset DISABLE_AUTO_COMPACT
input=$(printf '%s' "$input" | jq '.context_window.used_percentage=50')
marker 7 'marker also replaces a filled cell'
input=$(printf '%s' "$input" | jq 'del(.session_id) | .context_window={used_percentage:0,context_window_size:200000}')
marker 16 'no session id: unchanged 200k default at 167k'
input='{"context_window":{"used_percentage":"..","context_window_size":"1;exit"}}'
line=$(render)
[[ "$line" == *'0% · unknown'* ]] || fail 'malformed fields broke the line'
input='{broken}'
line=$(render)
[[ "$line" == *'0% · unknown'* ]] || fail 'malformed input broke the line'
input='[]'
line=$(render)
[[ "$line" == *'0% · unknown'* ]] || fail 'non-object input broke the line'
printf 'claude-statusline: all tests passed\n'
