#!/bin/bash
# Alt+V compose pane: the split and its pairing, focus toggling, and sending a
# draft to Claude, Codex, OpenCode, or a shell without touching the clipboard.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

ALT_V='\ev'
real_nvim=$(command -v nvim || true)

tk_start

# The compose pane's nvim records its environment and stays open.
nvim_log="$TEST_ROOT/nvim.log"
cat > "$TEST_ROOT/bin/nvim" <<STUB
#!/bin/bash
{
    printf 'prose=%s\n' "\$NVIM_PROSE"
    printf 'target=%s\n' "\$DOTFILES_COMPOSE_TARGET"
    printf 'draft=%s\n' "\$DOTFILES_COMPOSE_DRAFT"
    printf 'args=%s\n' "\$*"
} > "$nvim_log"
exec sleep 3600
STUB
chmod +x "$TEST_ROOT/bin/nvim"
compose() { TMUX="$TK_TMUX" "$DOTFILES_DIR/bin/tmux-compose" "$@"; }

claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$claude_log" --paste)")
tk_ready "$claude_log"

# Alt+V splits below and pairs the panes; the draft is named by the server's
# start time and the pane, under XDG state, private; nvim listens under the
# runtime directory.
tk_raw "$ALT_V"
tk_until test -s "$nvim_log" || fail "Alt+V opened no compose pane"
draft="$XDG_STATE_HOME/dotfiles/compose/$(ti display-message -p '#{start_time}')-${claude#%}.md"
grep -qx 'prose=1' "$nvim_log" || fail "NVIM_PROSE: $(cat "$nvim_log")"
grep -qx "target=$claude" "$nvim_log" || fail "compose target: $(cat "$nvim_log")"
grep -qx "draft=$draft" "$nvim_log" || fail "draft path: $(cat "$nvim_log")"
socket="$XDG_RUNTIME_DIR/dotfiles-compose/${draft##*/}.sock"
grep -qx "args=--listen $socket -- $draft" "$nvim_log" || fail "nvim arguments: $(cat "$nvim_log")"
assert_eq "$(stat -c %a "$draft")" 600 "draft mode"
pane=$(ti show -pqv -t "$claude" @compose_pane)
assert_eq "$(ti show -pqv -t "$pane" @compose_target)" "$claude" "@compose_target"
assert_eq "$(ti show -pqv -t "$pane" @compose_socket)" "$socket" "@compose_socket"
assert_eq "$(stat -c %a "${socket%/*}")" 700 "socket directory mode"
tk_wait '#{pane_id}' "$pane"
assert_eq "$(ti display-message -p -t "$pane" '#{pane_at_bottom}')" 1 "compose pane is below"

# Alt+V moves focus back and forth without another split.
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$claude"
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$pane"
assert_eq "$(ti display-message -p -t "$claude" '#{window_panes}')" 2 "a toggle split again"

# Send: a bracketed paste, then each agent's non-interrupting submit key; a
# shell only gets the paste. Nothing reaches the clipboard, no buffer remains.
tk_mark
printf 'hello world\n' > "$draft"
compose send "$claude" "$draft"
tk_expect '^[[200~hello world^[[201~^X^M' "send to Claude" tk_input "$claude_log"

declare -A submitted=([codex]='^I' [opencode]='^X^M' [bash]='')
for program in codex opencode bash; do
    log="$TEST_ROOT/$program.log"
    target=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub "$program" "$log" --paste)")
    tk_ready "$log"
    tk_wait '#{pane_current_command}' "$program" "$target"
    printf 'to %s\n' "$program" > "$TEST_ROOT/draft-$program.md"
    compose send "$target" "$TEST_ROOT/draft-$program.md"
    tk_expect "^[[200~to $program^[[201~${submitted[$program]}" "send to $program" tk_input "$log"
done
stage_log="$TEST_ROOT/bash.log"
: > "$stage_log"
compose stage "$target" "$TEST_ROOT/draft-bash.md"
tk_expect '^[[200~to bash^[[201~' "stage" tk_input "$stage_log"

sleep 0.3
assert_eq "$(tk_osc52)" "" "a compose paste reached the clipboard"
[[ "$(ti list-buffers -F '#{buffer_name}')" != *compose-* ]] || fail "a compose buffer was left behind"
grep -q 'hello world' "$XDG_STATE_HOME/dotfiles/compose/history.md" || fail "history did not record the prompt"
assert_eq "$(stat -c %a "$XDG_STATE_HOME/dotfiles/compose/history.md")" 600 "history mode"

# An empty draft or a dead target fails and keeps the draft.
: > "$TEST_ROOT/empty.md"
if compose send "$claude" "$TEST_ROOT/empty.md" 2>/dev/null; then fail "an empty draft was sent"; fi
printf 'keep me\n' > "$TEST_ROOT/kept.md"
ti kill-pane -t "$target"
if compose send "$target" "$TEST_ROOT/kept.md" 2>/dev/null; then fail "sent to a dead pane"; fi
assert_eq "$(cat "$TEST_ROOT/kept.md")" 'keep me' "draft after a failed send"

# Scroll keys are forwarded to the agent.
: > "$claude_log"
compose forward "$claude" PPage
tk_expect '^[[5~' "forwarded PgUp" tk_input "$claude_log"

# With real nvim and the prose profile: Ctrl+Shift+S, as WezTerm sends it,
# stages; Ctrl+S sends; each clears the draft.
if [[ -n "$real_nvim" ]]; then
    rm "$TEST_ROOT/bin/nvim"
    ln -s "$real_nvim" "$TEST_ROOT/bin/nvim"
    mkdir -p "$XDG_CONFIG_HOME/nvim"
    ln -s "$DOTFILES_DIR/configs/init.vim" "$XDG_CONFIG_HOME/nvim/init.vim"
    agent_log="$TEST_ROOT/agent.log"
    agent=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$agent_log" --paste)")
    tk_ready "$agent_log"
    tk_raw "$ALT_V"
    tk_wait '#{pane_current_command}' nvim
    editor=$(ti show -pqv -t "$agent" @compose_pane)
    tk_until tk_contains INSERT ti capture-pane -p -t "$editor" || fail "compose nvim did not start in insert mode"
    if [[ "$(ti display-message -p -t "$editor" '#{pane_key_mode}')" == 'Ext 2' ]]; then
        tk_raw 'staged words\e[27;6;83~'
        tk_expect '^[[200~staged words^[[201~' "Ctrl+Shift+S stages" tk_input "$agent_log"
        : > "$agent_log"
    fi
    tk_raw 'sent words\x13'
    tk_expect '^[[200~sent words^[[201~^X^M' "Ctrl+S sends" tk_input "$agent_log"
    draft="$XDG_STATE_HOME/dotfiles/compose/$(ti display-message -p '#{start_time}')-${agent#%}.md"
    tk_expect '' "draft after sending" cat "$draft"
fi

printf 'tmux-compose: ok\n'
