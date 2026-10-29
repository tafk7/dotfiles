#!/bin/bash
# Alt+I command drafting (shell/tools/ai-command.sh, bin/ai-command) against a
# stub Claude: the backend's Claude invocation and output checks, the widget
# state in Bash and Zsh, bindings and re-sourcing, and both shells driven with
# raw keys through a client of a tmux server running the tracked tmux.conf.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/tmux-keys.sh"
tk_start

# The stub goes in the disposable checkout's bin/, which shell/env.sh puts
# first on PATH. Shells and the backend run without the caller's PATH (tmux
# needs it), so no real claude can answer, wherever one is installed.
export AI_STUB_DIR="$TEST_ROOT/stub"
mkdir -p "$AI_STUB_DIR" "$TEST_ROOT/work/sub"
printf '#!/bin/sh\nexec python3 %q "$@"\n' "$ROOT/tests/lib/claude-stub.py" > "$DOTFILES_DIR/bin/claude"
chmod +x "$DOTFILES_DIR/bin/claude"
SHELL_PATH="$DOTFILES_DIR/bin:$TEST_SYSTEM_PATH"
unset AI_COMMAND_BACKEND AI_COMMAND_MODEL AI_COMMAND_EFFORT AI_COMMAND_TIMEOUT
for entry in profile.sh:.profile bash.sh:.bashrc bash_profile:.bash_profile zshenv:.zshenv zsh.sh:.zshrc zprofile:.zprofile; do
    ln -s "$DOTFILES_DIR/entry/${entry%%:*}" "$HOME/${entry#*:}"
done

stub_reset() { rm -rf -- "${AI_STUB_DIR:?}"/*; }
stub_calls() { if [[ -f "$AI_STUB_DIR/calls.jsonl" ]]; then wc -l < "$AI_STUB_DIR/calls.jsonl"; else echo 0; fi; }
calls_are() { [[ "$(stub_calls)" == "$1" ]]; }
# This run's slow stub has exited, or never got as far as waiting.
stub_gone() { [[ ! -s "$AI_STUB_DIR/slow.pid" ]] || ! kill -0 "$(<"$AI_STUB_DIR/slow.pid")" 2>/dev/null; }

# stub_call N EXPR: a Python expression over call N (-1 is the last): argv,
# stdin, cwd, and opt(NAME), the value after option NAME ('' if absent).
stub_call() {
    python3 - "$AI_STUB_DIR/calls.jsonl" "$1" "$2" <<'PY'
import json, sys
calls = [json.loads(line) for line in open(sys.argv[1])]
n = int(sys.argv[2])
call = calls[n - 1 if n > 0 else n]
argv = call["argv"]
def opt(name):
    return argv[argv.index(name) + 1] if name in argv else ""
print(eval(sys.argv[3], {"argv": argv, "stdin": call["stdin"], "cwd": call["cwd"], "opt": opt}))
PY
}

stdin_has() { [[ "$(stub_call "$1" stdin)" == *"$2"* ]] || fail "call $1 stdin lacks '$2': $(stub_call "$1" stdin)"; }

backend() { PATH="$SHELL_PATH" "$DOTFILES_DIR/bin/ai-command" "$@"; }

# expect_failure LABEL WANT ARGS...: exit 1, nothing on stdout, and one
# stderr line starting "ai-command: " that contains WANT.
expect_failure() {
    local label="$1" want="$2" out err rc=0
    shift 2
    out=$(backend "$@" 2>"$TEST_ROOT/stderr") || rc=$?
    err=$(<"$TEST_ROOT/stderr")
    assert_eq "$rc" 1 "$label: exit status"
    assert_eq "$out" "" "$label: stdout"
    [[ "$err" == "ai-command: "*"$want"* && "$err" != *$'\n'* ]] || fail "$label: stderr: $err"
}

# --- Backend: the Claude invocation.
session=$(</proc/sys/kernel/random/uuid)
assert_eq "$(CLAUDE_FLAGS=--dangerously-skip-permissions backend --session "$session" \
    --shell "bash 5.2" --cwd /work 'find every JSON file')" "echo stub 1" "first command"
argv=$(stub_call 1 '"|".join(argv)')
[[ "|$argv|" == *"|-p|"* && "$argv" == *"|--safe-mode|"* ]] || fail "not print mode with --safe-mode: $argv"
[[ "$argv" == *"|--tools||"* ]] || fail "tools not disabled: $argv"
[[ "$argv" == *"|--setting-sources|user|"* && "$argv" == *"|--strict-mcp-config|"* ]] || fail "settings or MCP not isolated: $argv"
[[ "$argv" == *"|--permission-mode|dontAsk|"* ]] || fail "permission mode: $argv"
[[ "$argv" == *"|--output-format|json|--json-schema|"* ]] || fail "no structured output: $argv"
[[ "$argv" == *"|--model|haiku|"* && "$argv" == *"|--effort|low" ]] || fail "model and effort defaults: $argv"
[[ "$argv" != *--continue* && "$argv" != *--resume* && "$argv" != *dangerously* ]] || fail "unsafe flags: $argv"
assert_eq "$(stub_call 1 'opt("--session-id")')" "$session" "new conversation id"
[[ "$(stub_call 1 'opt("--system-prompt")')" == "You draft shell commands"*"never run anything"* ]] \
    || fail "system prompt: $(stub_call 1 'opt("--system-prompt")')"
assert_eq "$(stub_call 1 cwd)" "$XDG_CACHE_HOME/dotfiles/ai-command" "Claude's working directory"
for text in "Shell: bash 5.2" "System: ubuntu 24.04, " "Working directory: /work" "Request: find every JSON file"; do
    stdin_has 1 "$text"
done

# A correction resumes the exact conversation, with the command line.
assert_eq "$(printf 'use absolute paths\0echo stub 1 | sort' | backend --stdin --session "$session" --resume --edited)" \
    "echo stub 2" "correction"
assert_eq "$(stub_call 2 'opt("--resume")')/$(stub_call 2 'opt("--session-id")')" "$session/" "resumed conversation"
for text in "I edited your last command" $'<command-line>\necho stub 1 | sort\n</command-line>' "Correction: use absolute paths"; do
    stdin_has 2 "$text"
done
[[ "$(stub_call 2 stdin)" != *"Shell:"* ]] || fail "a correction repeated the context"
printf 'quote it\0echo stub 2' | backend --stdin --session "$session" --resume >/dev/null
stdin_has 3 "The command line still reads"

# Overrides; empty leaves Claude's own choice. Without --session nothing is kept.
AI_COMMAND_MODEL=sonnet AI_COMMAND_EFFORT='' backend 'list ports' >/dev/null
argv=$(stub_call -1 '"|".join(argv)')
[[ "$argv" == *"|--model|sonnet|"* || "$argv" == *"|--model|sonnet" ]] || fail "model override: $argv"
[[ "$argv" != *--effort* && "$argv" == *"|--no-session-persistence|"* ]] || fail "effort or persistence: $argv"
AI_COMMAND_MODEL='' backend 'list ports' >/dev/null
[[ "$(stub_call -1 '"|".join(argv)')" != *--model* ]] || fail "an empty model was passed"

# Output: exact multiline text, fences dropped.
printf 'for f in *.json; do\n\tjq . "$f"\ndone' > "$AI_STUB_DIR/reply"
assert_eq "$(backend loop)" $'for f in *.json; do\n\tjq . "$f"\ndone' "multiline command"
printf '```bash\nls -la\n```' > "$AI_STUB_DIR/reply"
assert_eq "$(backend list)" "ls -la" "fenced command"

# Rejected output and failures.
printf '   \n' > "$AI_STUB_DIR/reply"
expect_failure "empty command" "empty command" x
printf 'echo \033[2Jcleared' > "$AI_STUB_DIR/reply"
expect_failure "control characters" "control characters" x
rm "$AI_STUB_DIR/reply"
for mode in malformed plain; do
    printf '%s' "$mode" > "$AI_STUB_DIR/mode"
    expect_failure "$mode output" "malformed output" x
done
printf auth > "$AI_STUB_DIR/mode"
expect_failure "logged out" "Not logged in" x
printf fail > "$AI_STUB_DIR/mode"
expect_failure "nonzero exit" "claude failed: API Error: 529" x
printf wrong-session > "$AI_STUB_DIR/mode"
expect_failure "another session" "another session" --session "$(</proc/sys/kernel/random/uuid)" x
printf slow > "$AI_STUB_DIR/mode"
printf 5 > "$AI_STUB_DIR/sleep"
AI_COMMAND_TIMEOUT=1 expect_failure "timeout" "did not answer within 1s" x
rm "$AI_STUB_DIR/mode"
expect_failure "unknown session" "No conversation found" --session "$(</proc/sys/kernel/random/uuid)" --resume x
AI_COMMAND_BACKEND=codex expect_failure "unknown backend" "supported: claude" x
rc=0
err=$(PATH="$TEST_ROOT/no-such-dir" /usr/bin/python3 "$DOTFILES_DIR/bin/ai-command" x 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && "$err" == "ai-command: Claude Code not found"* ]] || fail "missing claude: $rc $err"
rc=0
backend --session not-a-uuid x >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 2 "invalid session id"

# --- Widget state, the same in both shells; not interactive, so no bindings.
for shell in bash zsh; do
    stub_reset
    if [[ "$shell" == bash ]]; then flags=(--noprofile --norc -c); else flags=(-fc); fi
    ids=$(PATH="$SHELL_PATH" "$shell" "${flags[@]}" '
        source "$DOTFILES_DIR/shell/tools/ai-command.sh"
        die() { printf "%s\n" "$*" >&2; exit 1; }
        expect() { [[ "$1" == "$2" ]] || die "$3: expected [$2], got [$1]"; }
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            expect "$(bindkey -M emacs "^[i")" "\"^[i\" undefined-key" "binding"
            expect "${precmd_functions[*]:-}" "" "precmd hook"
        else
            expect "$(bind -X 2>/dev/null)" "" "binding"
            expect "${PROMPT_COMMAND:-}" "" "prompt hook"
        fi
        cd "$1"
        ! _ai_command_plan "  " || die "an empty buffer was accepted"
        expect "$_ai_command_out" "ai-command: type a request first" "empty buffer"
        _ai_command_plan "find json files"
        expect "$_ai_command_mode" new "a request"
        _ai_command_send "find json files" || die "request: $_ai_command_out"
        expect "$_ai_command_out/$_AI_COMMAND_ACTIVE" "echo stub 1/1" "first command"
        first=$_AI_COMMAND_SESSION_ID
        _ai_command_plan "echo stub 1 --mine"
        expect "$_ai_command_mode" refine "a correction"
        _ai_command_send "echo stub 1 --mine" "use absolute paths" || die "correction: $_ai_command_out"
        expect "$_AI_COMMAND_SESSION_ID/$_ai_command_out" "$first/echo stub 2" "corrected command"
        cd sub
        _ai_command_plan "echo stub 2"
        expect "$_ai_command_mode" restart "a correction in another directory"
        _ai_command_send "echo stub 2" "add -print" || die "restart: $_ai_command_out"
        second=$_AI_COMMAND_SESSION_ID
        [[ -n "$second" && "$second" != "$first" ]] || die "the directory change kept the conversation"
        printf fail > "$AI_STUB_DIR/mode"
        _ai_command_plan "echo stub 3"
        ! _ai_command_send "echo stub 3" "again" || die "a failed turn succeeded"
        expect "$_ai_command_out" "ai-command: claude failed: API Error: 529 overloaded (stub)" "failure"
        expect "$_AI_COMMAND_SESSION_ID/$_AI_COMMAND_ACTIVE/$_AI_COMMAND_LAST_RESULT" "/1/echo stub 3" "state after a failure"
        _ai_command_plan "echo stub 3"
        # Ctrl+C the trap took before the backend started: the turn is cancelled
        # and no request is made.
        calls=$(wc -l < "$AI_STUB_DIR/calls.jsonl")
        _ai_command_interrupted=1
        ! _ai_command_send "echo stub 3" "again" || die "an interrupted turn succeeded"
        expect "$_ai_command_out/$(wc -l < "$AI_STUB_DIR/calls.jsonl")" "ai-command: cancelled/$calls" "Ctrl+C before the request"
        _ai_command_interrupted=0
        rm "$AI_STUB_DIR/mode"
        _ai_command_plan "echo stub 3"
        expect "$_ai_command_mode" restart "a correction after a failure"
        _ai_command_send "echo stub 3" "again" || die "retry: $_ai_command_out"
        third=$_AI_COMMAND_SESSION_ID
        source "$DOTFILES_DIR/shell/tools/ai-command.sh"
        expect "$_AI_COMMAND_SESSION_ID/$_AI_COMMAND_ACTIVE/$_AI_COMMAND_CWD" "$third/1/$PWD" "state after re-sourcing"
        _ai_command_reset
        _ai_command_plan "echo stub 5"
        expect "$_ai_command_mode/$_AI_COMMAND_SESSION_ID" new/ "after a reset"
        DOTFILES_DIR=/missing
        ! _ai_command_send x || die "a missing backend succeeded"
        expect "$_ai_command_out" "ai-command: /missing/bin/ai-command is missing" "missing backend"
        printf "%s %s %s\n" "$first" "$second" "$third"
    ' _ "$TEST_ROOT/work") || fail "$shell widget state"
    read -r first second third <<< "$ids"
    assert_eq "$(stub_calls)" 5 "$shell backend calls"
    assert_eq "$(stub_call 1 'opt("--session-id")')" "$first" "$shell first conversation"
    stdin_has 1 "Shell: $shell"
    stdin_has 1 "Working directory: $TEST_ROOT/work"$'\n'
    assert_eq "$(stub_call 2 'opt("--resume")')" "$first" "$shell correction resumed"
    stdin_has 2 "I edited your last command"
    stdin_has 2 "echo stub 1 --mine"
    assert_eq "$(stub_call 3 'opt("--session-id")')" "$second" "$shell conversation after cd"
    stdin_has 3 "Working directory: $TEST_ROOT/work/sub"
    stdin_has 3 $'The command line reads:\n<command-line>\necho stub 2\n</command-line>\n\nCorrection: add -print'
    assert_eq "$(stub_call 4 'opt("--resume")')" "$second" "$shell failed correction"
    assert_eq "$(stub_call 5 'opt("--session-id")')" "$third" "$shell conversation after a failure"
done

# The Bash widget itself, without a terminal: buffer, cursor, INT trap.
stub_reset
PATH="$SHELL_PATH" setsid -w bash --noprofile --norc -c '
    source "$DOTFILES_DIR/shell/tools/ai-command.sh"
    die() { printf "%s\n" "$*" >&2; exit 1; }
    trap "echo sentinel" INT
    trap_before=$(trap -p INT)
    READLINE_LINE="list big files" READLINE_POINT=2
    _ai_command_widget
    [[ "$READLINE_LINE" == "echo stub 1" && "$READLINE_POINT" == 11 ]] || die "buffer: [$READLINE_LINE] at $READLINE_POINT"
    [[ "$(trap -p INT)" == "$trap_before" ]] || die "INT trap not restored: $(trap -p INT)"
    _ai_command_ask() { return 1; }
    _ai_command_widget
    [[ "$READLINE_LINE" == "echo stub 1" ]] || die "a cancelled correction changed the buffer"
    _ai_command_ask() { _ai_command_feedback="shorter"; }
    printf fail > "$AI_STUB_DIR/mode"
    _ai_command_widget
    [[ "$READLINE_LINE" == "echo stub 1" ]] || die "a failure changed the buffer: $READLINE_LINE"
    rm "$AI_STUB_DIR/mode"
    printf "%s" "$1" > "$AI_STUB_DIR/reply"
    _ai_command_widget
    [[ "$READLINE_LINE" == "$1" ]] || die "multiline: $READLINE_LINE"
' _ $'for f in a b; do\n  echo "$f"\ndone' || fail "bash widget"
assert_eq "$(stub_calls)" 3 "bash widget backend calls"

# --- Interactive shells: bindings once, after reload --soft too, and the
# other AI wrappers as their own files define them.
ai_definitions='alias cl clc clp cll cx cxc cxp oc ocr ocrc pic pir; '
bash_interactive=$(env -u SSH_CONNECTION HOME="$HOME" PATH="$SHELL_PATH" bash -i -c '
    reload --soft
    bind -X | grep -c _ai_command
    printf "%s\n%s\n" "$PROMPT_COMMAND" "${STARSHIP_PROMPT_COMMAND:-}" | grep -c _ai_command_reset
    '"$ai_definitions"'declare -f claude codex opencode pi' 2>/dev/null)
bash_plain=$(PATH="$SHELL_PATH" bash --noprofile --norc -c 'for f in claude codex opencode pi; do source "$DOTFILES_DIR/shell/tools/$f.sh"; done
    '"$ai_definitions"'declare -f claude codex opencode pi')
assert_eq "$(head -n 2 <<< "$bash_interactive" | tr '\n' ' ')" "2 1 " "bash bindings and hook"
assert_eq "$(tail -n +3 <<< "$bash_interactive")" "$bash_plain" "bash AI wrappers"
# bash 5.2's bind -X puts a colon after the key sequence; 5.1's doesn't.
assert_eq "$(env -u SSH_CONNECTION HOME="$HOME" PATH="$SHELL_PATH" bash -i -c 'bind -X | grep _ai_command' 2>/dev/null | sed 's/": "/" "/')" \
    $'"\\eI" "_ai_command_reset_widget"\n"\\ei" "_ai_command_widget"' "bash key sequences"
zsh_interactive=$(env -u SSH_CONNECTION HOME="$HOME" PATH="$SHELL_PATH" zsh -i -c '
    reload --soft
    bindkey -M emacs "^[i"; bindkey -M emacs "^[I"
    print -l $precmd_functions | grep -c _ai_command_reset
    '"$ai_definitions"'functions claude codex opencode pi' 2>/dev/null)
zsh_plain=$(PATH="$SHELL_PATH" zsh -fc 'for f in claude codex opencode pi; do source "$DOTFILES_DIR/shell/tools/$f.sh"; done
    '"$ai_definitions"'functions claude codex opencode pi')
assert_eq "$(head -n 3 <<< "$zsh_interactive" | tr '\n' ' ')" '"^[i" ai-command "^[I" ai-command-reset 1 ' "zsh bindings and hook"
assert_eq "$(tail -n +4 <<< "$zsh_interactive")" "$zsh_plain" "zsh AI wrappers"

# --- Key collisions: tmux and WezTerm leave Alt+I and Alt+Shift+I to the
# shell.
root_keys=$(ti list-keys -T root)
grep -qE '^bind-key +(-r +)?-T root +M-e ' <<< "$root_keys" || fail "tmux root table not as expected: $root_keys"
! grep -E '^bind-key +(-r +)?-T root +M-[iI] ' <<< "$root_keys" || fail "tmux binds M-i or M-I"
! grep -nE "key = ['\"][iI]['\"]" "$ROOT/configs/wezterm.lua" || fail "WezTerm binds an I key"

# --- Both shells for real: raw keys through the tracked tmux.conf.
# command_line: the last screen line with the prompt on it.
command_line() { ti capture-pane -p -t "$pane" | grep -F "$prompt" | tail -n 1; }
expect_line() { [[ "$(command_line)" == *"$1" ]] || fail "$shell: $2: $(ti capture-pane -p -t "$pane")"; }

# e2e SHELL PROMPT: PROMPT is how the shell's prompt ends on screen.
e2e() {
    local shell="$1" prompt="$2" pane first second screen next
    stub_reset
    pane=$(ti new-window -t test -P -F '#{pane_id}' -c "$TEST_ROOT/work" \
        "env -u SSH_CONNECTION HOME=$(printf %q "$HOME") PATH=$(printf %q "$SHELL_PATH") AI_STUB_DIR=$(printf %q "$AI_STUB_DIR") $shell -i")
    tk_until tk_screen_has "$prompt" "$pane" || fail "$shell: no prompt: $(ti capture-pane -p -t "$pane")"

    # Alt+I: the request becomes the command, which does not run.
    printf 'touch %q/executed-{n}' "$TEST_ROOT" > "$AI_STUB_DIR/reply"
    tk_raw 'find every json file\ei'
    tk_until tk_screen_has "executed-1" "$pane" || fail "$shell: no command: $(ti capture-pane -p -t "$pane")"
    expect_line "touch $TEST_ROOT/executed-1" "the command did not replace the request"
    sleep 0.3
    [[ ! -e "$TEST_ROOT/executed-1" ]] || fail "$shell: the drafted command ran"
    first=$(stub_call 1 'opt("--session-id")')
    [[ -n "$first" ]] || fail "$shell: first request had no session id"
    stdin_has 1 "Request: find every json file"

    # Alt+I again: a correction to the edited command, same conversation.
    tk_raw ' # mine\ei'
    tk_until tk_screen_has 'refine>' "$pane" || fail "$shell: no refine prompt: $(ti capture-pane -p -t "$pane")"
    tk_raw 'use absolute paths\r'
    tk_until tk_screen_has "executed-2" "$pane" || fail "$shell: no corrected command: $(ti capture-pane -p -t "$pane")"
    expect_line "touch $TEST_ROOT/executed-2" "the corrected command did not replace the command line"
    assert_eq "$(stub_call 2 'opt("--resume")')" "$first" "$shell correction session"
    stdin_has 2 "executed-1 # mine"
    stdin_has 2 "Correction: use absolute paths"
    tk_until tk_lacks 'refine>' ti capture-pane -p -t "$pane" || fail "$shell: refine prompt left on screen"

    # A cancelled or empty correction changes nothing.
    tk_raw '\ei'
    tk_until tk_screen_has 'refine>' "$pane" || fail "$shell: no refine prompt for Ctrl+C"
    tk_raw 'never mind\003'
    tk_until tk_lacks 'refine>' ti capture-pane -p -t "$pane" || fail "$shell: Ctrl+C left the refine prompt"
    tk_raw '\ei'
    tk_until tk_screen_has 'refine>' "$pane" || fail "$shell: no refine prompt for Enter"
    tk_raw '\r'
    tk_until tk_lacks 'refine>' ti capture-pane -p -t "$pane" || fail "$shell: Enter left the refine prompt"
    sleep 0.3
    assert_eq "$(stub_calls)" 2 "$shell calls after cancelled corrections"
    expect_line "executed-2" "a cancelled correction changed the command line"

    # Ctrl+C while Claude is asked: the command line stays.
    printf slow > "$AI_STUB_DIR/mode"
    tk_raw '\ei'
    tk_until tk_screen_has 'refine>' "$pane" || fail "$shell: no refine prompt before the slow call"
    tk_raw 'slower\r'
    tk_until tk_screen_has 'ai-command: asking claude... (Ctrl+C cancels)' "$pane" || fail "$shell: no status"
    # Once the request is under way; Ctrl+C before it starts is checked below.
    tk_until test -s "$AI_STUB_DIR/slow.pid" || fail "$shell: the slow request never started"
    tk_raw '\003'
    tk_until tk_screen_has 'ai-command: cancelled' "$pane" || fail "$shell: no cancel message: $(ti capture-pane -p -t "$pane")"
    tk_until tk_lacks 'asking claude' ti capture-pane -p -t "$pane" || fail "$shell: status left on screen"
    expect_line "executed-2" "Ctrl+C changed the command line"
    tk_until stub_gone || fail "$shell: the interrupted request kept running"

    # A failure says so and keeps the command line; the next correction starts over.
    printf fail > "$AI_STUB_DIR/mode"
    tk_raw '\ei'
    tk_until tk_screen_has 'refine>' "$pane" || fail "$shell: no refine prompt after Ctrl+C"
    tk_raw 'again\r'
    tk_until tk_screen_has 'ai-command: claude failed: API Error: 529' "$pane" || fail "$shell: no failure message"
    expect_line "executed-2" "a failure changed the command line"
    rm "$AI_STUB_DIR/mode"

    # Alt+Shift+I: the command line becomes a new request.
    tk_raw '\eI'
    tk_until tk_screen_has 'next Alt+I starts a new conversation' "$pane" || fail "$shell: no reset message"
    next=$(( $(stub_calls) + 1 ))
    tk_raw '\ei'
    tk_until tk_screen_has "executed-$next" "$pane" || fail "$shell: nothing after reset: $(ti capture-pane -p -t "$pane")"
    second=$(stub_call -1 'opt("--session-id")')
    [[ -n "$second" && "$second" != "$first" ]] || fail "$shell: reset kept the conversation"
    stdin_has -1 "Request: touch"

    # Running a command ends the conversation; a multiline command runs whole.
    printf 'for f in a b; do\n  echo "item-$f"\ndone' > "$AI_STUB_DIR/reply"
    tk_raw '\003'
    tk_raw 'loop over a and b\ei'
    tk_until tk_screen_has '  echo "item-$f"' "$pane" || fail "$shell: no multiline command: $(ti capture-pane -p -t "$pane")"
    [[ -n "$(stub_call -1 'opt("--session-id")')" ]] || fail "$shell: a fresh prompt resumed the conversation"
    tk_raw '\r'
    tk_until tk_screen_has 'item-b' "$pane" || fail "$shell: the multiline command did not run: $(ti capture-pane -p -t "$pane")"
    next=$(( $(stub_calls) + 1 ))
    tk_raw 'list files\ei'
    tk_until calls_are "$next" || fail "$shell: no request after a command: $(ti capture-pane -p -t "$pane")"
    [[ -n "$(stub_call -1 'opt("--session-id")')" ]] || fail "$shell: a request after a command resumed the conversation"
    screen=$(ti capture-pane -p -t "$pane")
    [[ "$screen" != *$'\e'* ]] || fail "$shell: escape sequences on screen"
    ti kill-pane -t "$pane"
}

e2e bash 'work $'
e2e zsh 'work %'

printf 'ai-command: ok\n'
