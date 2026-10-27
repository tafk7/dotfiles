#!/bin/bash
# Compose joined to an agent's prompt box through its external-editor key and
# $VISUAL (bin/compose-editor): Claude's Ctrl+G, Codex's Ctrl+E, OpenCode's
# Ctrl+X e. Pulling the box into a new or open compose pane, putting the draft
# back on quit, a request the agent doesn't take, :cq, Ctrl+Shift+G, and
# compose-editor running $EDITOR for every other file.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

ALT_V='\ev'
CTRL_SHIFT_G='\e[27;6;71~'
real_nvim=$(command -v nvim || true)

tk_start
VISUAL_EDITOR="$DOTFILES_DIR/bin/compose-editor"
compose() { TMUX="$TK_TMUX" "$DOTFILES_DIR/bin/tmux-compose" "$@"; }
box() { cat "$1.box" 2>/dev/null; }
has_compose() { [[ -n "$(ti show -pqv -t "$1" @compose_pane)" ]]; }
draft_for() { printf '%s/dotfiles/compose/%s-%s.md' "$XDG_STATE_HOME" "$(ti display-message -p '#{start_time}')" "${1#%}"; }
now_us() { printf '%s' "${EPOCHREALTIME/./}"; }

# The compose pane's nvim records its environment and stays open; run by an
# agent's editor key instead (no target), it writes the prompt and exits.
nvim_log="$TEST_ROOT/nvim.log"
cat > "$TEST_ROOT/bin/nvim" <<STUB
#!/bin/bash
{
    printf 'prose=%s\n' "\$NVIM_PROSE"
    printf 'target=%s\n' "\${DOTFILES_COMPOSE_TARGET-}"
    printf 'args=%s\n' "\$*"
} > "$nvim_log"
[[ -n "\${DOTFILES_COMPOSE_TARGET-}" ]] && exec sleep 3600
printf 'from fullscreen' > "\${@: -1}"
STUB
chmod +x "$TEST_ROOT/bin/nvim"

# A program that runs its arguments as a child under NAME, as an agent runs
# $VISUAL.
cat > "$TEST_ROOT/bin/as-agent" <<'EOF'
#!/bin/bash
name="$1"
shift
exec -a "$name" bash -c '"$@"; exit $?' bash "$@"
EOF
cat > "$TEST_ROOT/bin/plain-editor" <<'EOF'
#!/bin/bash
printf 'edited by plain-editor\n' > "${@: -1}"
EOF
chmod +x "$TEST_ROOT/bin/as-agent" "$TEST_ROOT/bin/plain-editor"

claude_log="$TEST_ROOT/claude.log"
claude=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
    "$(tk_stub claude "$claude_log" --paste --editor)")
tk_ready "$claude_log"
tk_wait '#{pane_current_command}' claude "$claude"
draft=$(draft_for "$claude")

# Ctrl+G moves the box into a new compose pane's draft and empties the box.
tk_raw 'half typed\a'
tk_until test -s "$nvim_log" || fail "Ctrl+G opened no compose pane"
grep -qx "target=$claude" "$nvim_log" || fail "compose target: $(cat "$nvim_log")"
tk_until has_compose "$claude" || fail "@compose_pane never set"
pane=$(ti show -pqv -t "$claude" @compose_pane)
tk_wait '#{pane_id}' "$pane"
assert_eq "$(cat "$draft")" 'half typed' "draft after Ctrl+G"
assert_eq "$(box "$claude_log")" '' "box after Ctrl+G"
assert_eq "$(stat -c %a "$draft")" 600 "draft mode"
assert_eq "$(ti show -pqv -t "$claude" @compose-editor)" '' "@compose-editor after a pull"

# Alt+V from Claude goes through Ctrl+G too: the box joins the end of the draft
# and focus moves to the open pane, with no second split.
ti select-pane -t "$claude"
tk_raw 'more words'
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$pane"
assert_eq "$(cat "$draft")" $'half typed\n\nmore words' "draft after Alt+V"
assert_eq "$(box "$claude_log")" '' "box after Alt+V"
assert_eq "$(ti display-message -p -t "$claude" '#{window_panes}')" 2 "Alt+V split again"

# Returning puts the draft in the box, ahead of anything typed there since,
# and empties the draft. The agent takes it after `return` has gone, so nvim
# quits at once.
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$claude"
tk_raw 'typed meanwhile'
tk_until grep -q meanwhile "$claude_log" || fail "Claude stub got no input"
compose return "$claude" "$draft"
tk_expect $'half typed\n\nmore words\n\ntyped meanwhile' "box after return" box "$claude_log"
tk_expect '' "draft after return" cat "$draft"
tk_expect '' "@compose-editor after return" ti show -pqv -t "$claude" @compose-editor

# A round trip with nothing typed meanwhile gives the box back as it was.
text=$'half typed\n\nmore words\n\ntyped meanwhile'
tk_raw '\a'
tk_wait '#{pane_id}' "$pane"
assert_eq "$(cat "$draft")" "$text" "draft after another Ctrl+G"
assert_eq "$(box "$claude_log")" '' "box after another Ctrl+G"
compose return "$claude" "$draft"
tk_expect "$text" "box after a round trip" box "$claude_log"
tk_expect '' "draft after a round trip" cat "$draft"

# Ctrl+Shift+G opens nvim with the prose profile in Claude's place; whatever it
# writes becomes the box.
: > "$nvim_log"
ti select-pane -t "$claude"
tk_raw "$CTRL_SHIFT_G"
tk_until test -s "$nvim_log" || fail "Ctrl+Shift+G ran no nvim"
grep -qx 'prose=1' "$nvim_log" || fail "fullscreen NVIM_PROSE: $(cat "$nvim_log")"
grep -qx 'target=' "$nvim_log" || fail "fullscreen had a compose target: $(cat "$nvim_log")"
tk_expect 'from fullscreen' "box after Ctrl+Shift+G" box "$claude_log"
assert_eq "$(ti display-message -p -t "$claude" '#{window_panes}')" 2 "Ctrl+Shift+G split"

# Every other file an agent opens with $VISUAL gets $EDITOR and leaves the
# draft alone: Claude's transcript (v in its Ctrl+O view), a plan, CLAUDE.md;
# and so does anything outside an agent.
printf 'keep\n' > "$draft"
for file in "$TMPDIR/cc-transcript-1.txt" "$TEST_ROOT/plan.md" "$TEST_ROOT/CLAUDE.md"; do
    printf 'x\n' > "$file"
    TMUX="$TK_TMUX" TMUX_PANE="$claude" EDITOR=plain-editor as-agent claude "$VISUAL_EDITOR" "$file"
    assert_eq "$(cat "$file")" 'edited by plain-editor' "compose-editor on Claude's ${file##*/}"
done
printf 'x\n' > "$TEST_ROOT/notes.md"
TMUX="$TK_TMUX" TMUX_PANE="$claude" EDITOR=plain-editor as-agent codex "$VISUAL_EDITOR" "$TEST_ROOT/notes.md"
assert_eq "$(cat "$TEST_ROOT/notes.md")" 'edited by plain-editor' "compose-editor on Codex's other file"
printf 'x\n' > "$TEST_ROOT/commit.txt"
TMUX="$TK_TMUX" TMUX_PANE="$claude" EDITOR=plain-editor "$VISUAL_EDITOR" "$TEST_ROOT/commit.txt"
assert_eq "$(cat "$TEST_ROOT/commit.txt")" 'edited by plain-editor' "compose-editor outside an agent"
assert_eq "$(cat "$draft")" 'keep' "draft after other files"
assert_eq "$(ti display-message -p -t "$claude" '#{window_panes}')" 2 "other files split"
: > "$draft"

# A Claude that doesn't run its editor (a dialog or its transcript view has
# the key): `return` doesn't wait for it, and after 3 s the request is
# withdrawn with a message, the draft kept and nothing pasted. Alt+V still
# opens the pane, after a second, without the box.
deaf_log="$TEST_ROOT/deaf.log"
deaf=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
    "$(tk_stub claude "$deaf_log" --paste)")
tk_ready "$deaf_log"
tk_wait '#{pane_current_command}' claude "$deaf"
deaf_draft=$(draft_for "$deaf")
printf 'kept back\n' > "$deaf_draft"
start=$(now_us)
compose return "$deaf" "$deaf_draft"
(( $(now_us) - start < 1000000 )) || fail "return waited for the agent"
tk_expect '^G' "the editor key at a deaf Claude" tk_input "$deaf_log"
tk_expect 'push' "request while Claude might take it" ti show -pqv -t "$deaf" @compose-editor
tk_expect '' "request withdrawn" ti show -pqv -t "$deaf" @compose-editor
assert_eq "$(cat "$deaf_draft")" 'kept back' "draft Claude didn't take"
assert_eq "$(tk_input "$deaf_log")" '^G' "input of a deaf Claude"
tk_contains "didn't take the draft" tk_last_message || fail "no message for a draft not taken: $(tk_last_message)"
tk_raw "$ALT_V"
tk_until has_compose "$deaf" || fail "Alt+V opened no pane for a deaf Claude"
assert_eq "$(ti show -pqv -t "$deaf" @compose-editor)" '' "@compose-editor after a pull not taken"

# Without compose-editor as its VISUAL, Claude gets the plain compose pane and
# keeps its draft on quit; Ctrl+Shift+G outside an agent reaches the program.
plain_log="$TEST_ROOT/plain.log"
plain=$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub claude "$plain_log" --paste --editor)")
tk_ready "$plain_log"
tk_wait '#{pane_current_command}' claude "$plain"
tk_raw "$ALT_V"
tk_until has_compose "$plain" || fail "Alt+V opened no pane"
assert_eq "$(tk_input "$plain_log")" '' "Alt+V sent keys to a plain Claude"
plain_draft=$(draft_for "$plain")
printf 'parked\n' > "$plain_draft"
compose return "$plain" "$plain_draft"
assert_eq "$(cat "$plain_draft")" 'parked' "draft returned to a plain Claude"

app_log="$TEST_ROOT/app.log"
ti new-window -t test "$(tk_stub app "$app_log")"
tk_ready "$app_log"
tk_wait '#{pane_current_command}' app
tk_raw "${CTRL_SHIFT_G}x"
tk_until grep -q x "$app_log" || fail "app stub got no input"
assert_eq "$(tk_input "$app_log")" '^Gx' "Ctrl+Shift+G outside an agent"

# Codex: Ctrl+E and Alt+V pull, quitting returns, and Ctrl+Shift+G opens nvim in
# its place.
codex_log="$TEST_ROOT/codex.log"
codex=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
    "$(tk_stub codex "$codex_log" --paste --editor codex)")
tk_ready "$codex_log"
tk_wait '#{pane_current_command}' codex "$codex"
codex_draft=$(draft_for "$codex")
tk_raw 'codex words\x05'
tk_until has_compose "$codex" || fail "Ctrl+E opened no compose pane"
tk_wait '#{pane_id}' "$(ti show -pqv -t "$codex" @compose_pane)"
assert_eq "$(cat "$codex_draft")" 'codex words' "draft after Codex's Ctrl+E"
assert_eq "$(box "$codex_log")" '' "Codex box after Ctrl+E"
ti select-pane -t "$codex"
tk_raw 'and more'
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$(ti show -pqv -t "$codex" @compose_pane)"
assert_eq "$(cat "$codex_draft")" $'codex words\n\nand more' "draft after Alt+V in Codex"
compose return "$codex" "$codex_draft"
tk_expect $'codex words\n\nand more' "Codex box after return" box "$codex_log"
tk_expect '' "Codex draft after return" cat "$codex_draft"
ti select-pane -t "$codex"
: > "$nvim_log"
tk_raw "$CTRL_SHIFT_G"
tk_until test -s "$nvim_log" || fail "Ctrl+Shift+G ran no nvim in Codex"
grep -qx 'prose=1' "$nvim_log" || fail "Codex fullscreen NVIM_PROSE: $(cat "$nvim_log")"
tk_expect 'from fullscreen' "Codex box after Ctrl+Shift+G" box "$codex_log"

# OpenCode: Ctrl+X e and Alt+V pull, emptying the box with a lone newline (an
# empty file would leave it), quitting returns, and Ctrl+Shift+G opens nvim in
# its place. Without compose-editor, its Ctrl+Shift+G is its own editor key.
opencode_log="$TEST_ROOT/opencode.log"
opencode=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
    "$(tk_stub opencode "$opencode_log" --paste --editor opencode)")
tk_ready "$opencode_log"
tk_wait '#{pane_current_command}' opencode "$opencode"
opencode_draft=$(draft_for "$opencode")
tk_raw 'opencode words\x18e'
tk_until has_compose "$opencode" || fail "Ctrl+X e opened no compose pane"
tk_wait '#{pane_id}' "$(ti show -pqv -t "$opencode" @compose_pane)"
assert_eq "$(cat "$opencode_draft")" 'opencode words' "draft after OpenCode's Ctrl+X e"
assert_eq "$(box "$opencode_log")" '' "OpenCode box after Ctrl+X e"
ti select-pane -t "$opencode"
tk_raw 'and more'
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$(ti show -pqv -t "$opencode" @compose_pane)"
assert_eq "$(cat "$opencode_draft")" $'opencode words\n\nand more' "draft after Alt+V in OpenCode"
compose return "$opencode" "$opencode_draft"
tk_expect $'opencode words\n\nand more' "OpenCode box after return" box "$opencode_log"
tk_expect '' "OpenCode draft after return" cat "$opencode_draft"
: > "$nvim_log"
ti select-pane -t "$opencode"
tk_raw "$CTRL_SHIFT_G"
tk_until test -s "$nvim_log" || fail "Ctrl+Shift+G ran no nvim in OpenCode"
grep -qx 'prose=1' "$nvim_log" || fail "OpenCode fullscreen NVIM_PROSE: $(cat "$nvim_log")"
tk_expect 'from fullscreen' "OpenCode box after Ctrl+Shift+G" box "$opencode_log"

own_log="$TEST_ROOT/own.log"
ti new-window -t test "$(tk_stub opencode "$own_log" --paste)"
tk_ready "$own_log"
tk_wait '#{pane_current_command}' opencode
tk_raw "$CTRL_SHIFT_G"
tk_expect '^Xe' "Ctrl+Shift+G in an OpenCode without compose-editor" tk_input "$own_log"
own_codex_log="$TEST_ROOT/own-codex.log"
ti new-window -t test "$(tk_stub codex "$own_codex_log" --paste)"
tk_ready "$own_codex_log"
tk_wait '#{pane_current_command}' codex
tk_raw "$CTRL_SHIFT_G"
tk_expect '^E' "Ctrl+Shift+G in a Codex without compose-editor" tk_input "$own_codex_log"

# With real nvim: quitting puts the draft back, :cq keeps it, and a pull into
# an open pane shows up in nvim, where typing goes on after the pulled text.
if [[ -n "$real_nvim" ]]; then
    rm "$TEST_ROOT/bin/nvim"
    ln -s "$real_nvim" "$TEST_ROOT/bin/nvim"
    mkdir -p "$XDG_CONFIG_HOME/nvim"
    ln -s "$DOTFILES_DIR/configs/init.vim" "$XDG_CONFIG_HOME/nvim/init.vim"
    agent_log="$TEST_ROOT/agent.log"
    agent=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
        "$(tk_stub claude "$agent_log" --paste --editor)")
    tk_ready "$agent_log"
    tk_wait '#{pane_current_command}' claude "$agent"
    agent_draft=$(draft_for "$agent")
    open_editor() {
        tk_raw "$ALT_V"
        tk_wait '#{pane_current_command}' nvim
        editor=$(ti display-message -p '#{pane_id}')
        tk_until tk_contains INSERT ti capture-pane -p -t "$editor" || fail "compose nvim did not start"
    }

    tk_raw 'from the box'
    open_editor
    tk_until tk_screen_has 'from the box' "$editor" || fail "the box never reached nvim"
    tk_raw ' and more'
    tk_esc
    tk_raw ':q\r'
    tk_wait '#{window_panes}' 1 "$agent"
    tk_expect 'from the box and more' "box after :q" box "$agent_log"
    tk_expect '' "draft after :q" cat "$agent_draft"

    open_editor
    tk_until tk_screen_has 'from the box and more' "$editor" || fail "reopening did not pull the box"
    tk_esc
    tk_raw ':cq\r'
    tk_wait '#{window_panes}' 1 "$agent"
    assert_eq "$(box "$agent_log")" '' "box after :cq"
    assert_eq "$(cat "$agent_draft")" 'from the box and more' "draft after :cq"

    open_editor
    tk_esc
    tk_raw 'gg0i'
    ti select-pane -t "$agent"
    tk_raw 'late addition\a'
    tk_wait '#{pane_id}' "$editor"
    tk_until tk_screen_has 'late addition' "$editor" || fail "nvim did not reload the pulled box"
    tk_raw ' and on'
    tk_expect 'late addition and on' "typing after a pull" tail -n 1 "$agent_draft"
fi

printf 'tmux-compose-agents: ok\n'
