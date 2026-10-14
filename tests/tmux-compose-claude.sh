#!/bin/bash
# Compose joined to Claude's prompt box through its Ctrl+G and $VISUAL
# (bin/compose-editor): pulling the box into a new or open compose pane, putting
# the draft back on quit, the paste fallback, :cq, Ctrl+Shift+G, and
# compose-editor running $EDITOR for everything else.
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

# The compose pane's nvim records its environment and stays open; run by
# Claude's Ctrl+G instead (no target), it writes the prompt and exits.
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
# and empties the draft.
tk_raw "$ALT_V"
tk_wait '#{pane_id}' "$claude"
tk_raw 'typed meanwhile'
tk_until grep -q meanwhile "$claude_log" || fail "Claude stub got no input"
compose return "$claude" "$draft"
assert_eq "$(box "$claude_log")" $'half typed\n\nmore words\n\ntyped meanwhile' "box after return"
assert_eq "$(cat "$draft")" '' "draft after return"

# A round trip with nothing typed meanwhile gives the box back as it was.
text=$'half typed\n\nmore words\n\ntyped meanwhile'
tk_raw '\a'
tk_wait '#{pane_id}' "$pane"
assert_eq "$(cat "$draft")" "$text" "draft after another Ctrl+G"
assert_eq "$(box "$claude_log")" '' "box after another Ctrl+G"
compose return "$claude" "$draft"
assert_eq "$(box "$claude_log")" "$text" "box after a round trip"
assert_eq "$(cat "$draft")" '' "draft after a round trip"

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

# A Claude that doesn't run its editor (busy, say): after 3 s the draft is
# pasted instead, and Alt+V still opens the pane.
deaf_log="$TEST_ROOT/deaf.log"
deaf=$(ti new-window -t test -e "VISUAL=$VISUAL_EDITOR" -P -F '#{pane_id}' \
    "$(tk_stub claude "$deaf_log" --paste)")
tk_ready "$deaf_log"
tk_wait '#{pane_current_command}' claude "$deaf"
deaf_draft=$(draft_for "$deaf")
mkdir -p "$(dirname "$deaf_draft")"
printf 'pasted back\n' > "$deaf_draft"
compose return "$deaf" "$deaf_draft"
tk_expect '^G^[[200~pasted back^[[201~' "return without Claude's editor" tk_input "$deaf_log"
assert_eq "$(cat "$deaf_draft")" '' "draft after the paste fallback"
assert_eq "$(ti show -pqv -t "$deaf" @compose-editor)" '' "@compose-editor after the fallback"
tk_raw "$ALT_V"
tk_until has_compose "$deaf" || fail "Alt+V opened no pane for a deaf Claude"

# Without compose-editor as its VISUAL, Claude gets the plain compose pane and
# keeps its draft on quit; Ctrl+Shift+G outside Claude reaches the program.
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
assert_eq "$(tk_input "$app_log")" '^Gx' "Ctrl+Shift+G outside Claude"

# compose-editor runs $EDITOR unless Claude in tmux runs it.
cat > "$TEST_ROOT/bin/plain-editor" <<'EOF'
#!/bin/bash
printf 'edited by plain-editor\n' > "${@: -1}"
EOF
chmod +x "$TEST_ROOT/bin/plain-editor"
printf 'x\n' > "$TEST_ROOT/commit.txt"
TMUX="$TK_TMUX" TMUX_PANE="$claude" EDITOR=plain-editor "$VISUAL_EDITOR" "$TEST_ROOT/commit.txt"
assert_eq "$(cat "$TEST_ROOT/commit.txt")" 'edited by plain-editor' "compose-editor outside Claude"

# With real nvim: quitting puts the draft back, :cq keeps it, and a pull into
# an open pane shows up in nvim.
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
    assert_eq "$(cat "$agent_draft")" '' "draft after :q"

    open_editor
    tk_until tk_screen_has 'from the box and more' "$editor" || fail "reopening did not pull the box"
    tk_esc
    tk_raw ':cq\r'
    tk_wait '#{window_panes}' 1 "$agent"
    assert_eq "$(box "$agent_log")" '' "box after :cq"
    assert_eq "$(cat "$agent_draft")" 'from the box and more' "draft after :cq"

    open_editor
    ti select-pane -t "$agent"
    tk_raw 'late addition\a'
    tk_wait '#{pane_id}' "$editor"
    tk_until tk_screen_has 'late addition' "$editor" || fail "nvim did not reload the pulled box"
fi

printf 'tmux-compose-claude: ok\n'
