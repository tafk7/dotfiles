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
    # Trimmed real interactive rows, with only the model/argument varied.
    jq -c --arg sid "$sid" --arg n "$1" --arg model "${2:-Sonnet 5.5}" '
        .sessionId = $sid |
        if (.message.content | startswith("<command-name>")) then
            .message.content |= sub("<command-args>[^<]*"; "<command-args>" + $n)
        else .message.content = ("<local-command-stdout>Auto-compact window for " + $model +
            " set to " + $n + (if $n == "auto" then "" else " tokens" end) + "</local-command-stdout>") end' \
        "$TEST_REPO_ROOT/tests/fixtures/claude-autocompact.jsonl" >> "$transcript"
}

marker 19 'no record or live command: default 967k trigger'
write_record "$sid"
marker 3 'record supplies the applied 150k trigger, ignoring pending tuning'
write_record another-session
marker 19 'a record for another session is ignored'
write_record "$sid"
original_input=$input
input=$(printf '%s' "$input" | jq '.model={id:"claude-opus-5-5",display_name:"Opus 5.5"}')
cat "$TEST_REPO_ROOT/tests/fixtures/claude-autocompact.jsonl" > "$transcript"
marker 5 'trimmed real interactive result replaces the recorded launch: 267k trigger'
input=$(printf '%s' "$input" | jq '.model={id:"claude-opus-5-5[1m]",display_name:"Opus 5.5 (1M context)"}')
marker 5 '1M display suffix matches the canonical live model key'
input=$(printf '%s' "$input" | jq '.model={id:"claude-opus-5-5-20260101[1m]",display_name:"Opus 5.5 (1M context)"}')
marker 5 'dated 1M model retains the same live key'
input=$(printf '%s' "$input" | jq 'del(.model.display_name)')
marker 5 'model-id fallback removes the date and 1M suffix'
rm "$transcript" "$XDG_CACHE_HOME/claude-statusline/$key.json"
input=$original_input
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
{"type":"user","message":{"content":"<local-command-stdout>CLAUDE_CODE_AUTO_COMPACT_WINDOW is set and takes precedence.</local-command-stdout>"}}
{"type":"user","message":{"content":"<local-command-stdout>Couldn't parse 'nonsense'</local-command-stdout>"}}
{"type":"user","sessionId":"another-session","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to 833k tokens</local-command-stdout>"}}
JSONL
marker 10 'only applied commands for this session count'

# This response is emitted after saving the new user value, and Claude clears
# its launch setting afterwards. Resolve the settings chain for that model.
printf '{"modelSettings":{"claude-sonnet-5-5":{"autoCompactWindow":400000}}}\n' > "$HOME/.claude/settings.json"
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to 400k tokens, but a higher-priority override is active (900k tokens)</local-command-stdout>"}}
JSONL
marker 7 'override response clears cached live tuning and resolves the new user setting'
printf '{"autoCompactWindow":500000}\n' > "$project/.claude/settings.json"
marker 9 'override response uses the project setting instead of the record'
command_result 533000
marker 10 'plain live tuning still takes precedence over the project setting'
printf '{"modelSettings":{"claude-sonnet-5-5":{"autoCompactWindow":"auto"}}}\n' > "$HOME/.claude/settings.json"
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to auto in settings, but a higher-priority override is active (500k tokens)</local-command-stdout>"}}
JSONL
marker 9 'reset with an active project override resolves the settings chain'
rm "$HOME/.claude/settings.json" "$project/.claude/settings.json"
command_result 533000
marker 10 'a later plain result replaces the settings-chain fallback'
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

# Viewing a subagent must neither rewrite the main cache nor forget its value.
main_input=$input
subagent="$TEST_ROOT/session/subagents/agent-1.jsonl"
mkdir -p "${subagent%/*}"
printf '{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":10000}}}\n' > "$subagent"
input=$(printf '%s' "$main_input" | jq --arg tp "$subagent" '.transcript_path=$tp')
cache="$XDG_CACHE_HOME/claude-statusline/$key.json"
cache_before=$(sha256sum "$cache")
marker 10 'subagent view reads the main live value'
assert_eq "$(sha256sum "$cache")" "$cache_before" 'subagent view preserves the main cache bytes'
input=$main_input
marker 10 'main view retains its override after a subagent view'

# Native overrides belong to their model, including when each command has
# left the tail. A /model switch must preserve values for both models.
input=$(printf '%s' "$main_input" | jq '.model={id:"claude-opus-5-5",display_name:"Opus 5.5"}')
marker 3 'another model does not borrow the main model live value'
command_result 383k 'Opus 5.5'
marker 7 'second model receives its own live value'
head -c 100000 /dev/zero | tr '\0' x >> "$transcript"
printf '\n' >> "$transcript"
marker 7 'second model value survives leaving the tail'
input=$main_input
marker 10 'returning to the first model restores its cached value'
input=$(printf '%s' "$main_input" | jq '.model={id:"claude-opus-5-5",display_name:"Opus 5.5"}')
marker 7 'returning to the second model restores its cached value'
input=$main_input
command_result 283k
printf '{"unfinished":' >> "$transcript"
marker 5 'valid command survives damaged JSONL: 250k trigger'

# Truncation drops the cached live setting.
printf '\n' > "$transcript"
marker 3 'truncated transcript invalidates the override cache'
command_result auto
marker 19 'native reset clears the recorded launch override'
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5: 183k tokens (from settings)\nAuto-compact summarizes the conversation when context usage approaches this limit. The actual threshold is the minimum of this setting and your model's maximum context window.\nThe auto setting picks a window tuned for your model and is strongly recommended for the best cost and performance.</local-command-stdout>"}}
JSONL
marker 19 'bare autocompact reports state and leaves the applied override alone'

# A smaller model output reservation is used for live windows when recorded.
printf '\n' > "$transcript"
jq '.compaction = {trigger:150000, window:171000, reservation:21000}' "$record" > "$TEST_ROOT/new-record"
mv "$TEST_ROOT/new-record" "$record"
command_result 171k
marker 3 'live window uses the recorded 21k reserve'
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
marker 1 'live window applies the native percent override'
unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE

# Applied stdout is sufficient even when the command arguments left the tail.
printf '\n' > "$transcript"
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to 371k tokens</local-command-stdout>"}}
JSONL
marker 7 'applied interactive stdout alone: 350k trigger'
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

# Cache housekeeping is limited to owned files and a daily sweep on a changed
# main transcript. A second changed refresh does not repeat the sweep.
cache_dir="$XDG_CACHE_HOME/claude-statusline"
touch "$cache_dir/expired.json" "$cache_dir/.compact.expired" "$cache_dir/recent.json" "$cache_dir/unrelated"
touch -d '31 days ago' "$cache_dir/expired.json" "$cache_dir/.compact.expired" "$cache_dir/unrelated"
touch -d '2 days ago' "$cache_dir/.pruned"
printf '\n' >> "$transcript"
marker 7 'cache sweep keeps the live marker'
[[ ! -e "$cache_dir/expired.json" && ! -e "$cache_dir/.compact.expired" ]] || fail 'expired cache files survived'
[[ -e "$cache_dir/recent.json" && -e "$cache_dir/unrelated" ]] || fail 'cache sweep removed recent or unrelated files'
touch -d '31 days ago' "$cache_dir/next-day.json"
printf '\n' >> "$transcript"
marker 7 'same-day refresh does not repeat the cache sweep'
[[ -e "$cache_dir/next-day.json" ]] || fail 'cache sweep ran more than once per day'

# Abort a refresh exactly at the cache write, after mktemp. Its EXIT trap must
# remove the unfinished file, rather than leave debris until the next sweep.
jq_bin=$(command -v jq)
printf '#!/bin/bash\nif [[ "$1" == -n ]]; then kill -TERM "$PPID"; exit 1; fi\nexec %q "$@"\n' \
    "$jq_bin" > "$TEST_ROOT/bin/jq"
chmod +x "$TEST_ROOT/bin/jq"
printf '\n' >> "$transcript"
rc=0
{ printf '%s\n' "$input" | bash "$TEST_REPO_ROOT/configs/ai/claude/statusline.sh" >/dev/null 2>/dev/null; } 2>/dev/null || rc=$?
rm "$TEST_ROOT/bin/jq"
assert_eq "$rc" 143 'the cache write was interrupted by TERM'
for temporary in "$cache_dir"/.compact.*; do
    [[ ! -e "$temporary" ]] || fail 'interrupted refresh left its temporary cache file'
done

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
printf '{"autoCompactWindow":400000}\n' > "$HOME/.claude/settings.json"
cat >> "$transcript" <<'JSONL'
{"type":"user","message":{"content":"<local-command-stdout>Auto-compact window for Sonnet 5.5 set to 400k tokens, but a higher-priority override is active (900k tokens)</local-command-stdout>"}}
JSONL
line=$(STATUSLINE_INPUT="$input" STATUSLINE_SCRIPT="$TEST_REPO_ROOT/configs/ai/claude/statusline.sh" \
    "$TEST_ROOT/flag/claude" --autocompact 183000 | sed $'s/\033\\[[0-9;]*m//g')
bar=${line%% *}; before=${bar%%│*}
assert_eq "${#before}" 7 'override response drops the foreground flag and reads settings'
rm "$HOME/.claude/settings.json"
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
