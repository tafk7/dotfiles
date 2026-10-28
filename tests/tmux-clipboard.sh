#!/bin/bash
# Every tmux copy source reaches the tmux buffer and the client clipboard (OSC
# 52) through bin/tmux-copy.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

COPY='\e[2;5~'
PREFIX='\001'

tk_start

# Prove an export did not happen: send a sentinel through the explicit path and
# require it to be the only payload since the mark.
expect_no_osc52() {
    sleep 0.3
    printf sentinel | TMUX="$TK_TMUX" "$DOTFILES_DIR/bin/tmux-copy"
    tk_expect sentinel "$1" tk_osc52
}

select_line() {
    ti copy-mode -t test
    ti send -X -t test search-backward "$1"
    ti send -X -t test begin-selection
    ti send -X -t test end-of-line
}

ti respawn-pane -k -t test "printf 'alpha beta\nbravo copy\ncharlie key\nlarge payload here\n'; exec sleep 3600"
tk_until tk_screen_has 'large payload' test || fail "fixture text never appeared"

# copy-mode y: buffer and clipboard. This also proves copy-command finds
# DOTFILES_DIR in a checkout path with spaces.
tk_mark
select_line alpha
tk_raw y
tk_wait '#{pane_in_mode}' 0 test
assert_eq "$(ti show-buffer)" "alpha beta" "y sets the buffer"
tk_expect 'alpha beta' "copy-mode y" tk_osc52

# The Copy key in copy-mode.
tk_mark
select_line bravo
tk_raw "$COPY"
tk_wait '#{pane_in_mode}' 0 test
assert_eq "$(ti show-buffer)" "bravo copy" "Copy key sets the buffer"
tk_expect 'bravo copy' "Copy key" tk_osc52

# Alt+double-click copies the word under the pointer (row 3 is "charlie key").
tk_mark
tk_raw '\e[<8;3;3M\e[<8;3;3m\e[<8;3;3M\e[<8;3;3m'
tk_expect charlie "Alt+double-click" tk_osc52
assert_eq "$(ti show-buffer)" charlie "Alt+double-click sets the buffer"

# External load-buffer (nvim, shell cuts, Claude): automatic names export,
# named buffers stay in tmux.
tk_mark
printf 'from nvim' | ti load-buffer -
tk_expect 'from nvim' "after-load-buffer hook" tk_osc52
tk_mark
printf 'compose text' | ti load-buffer -b compose-1 -
expect_no_osc52 "named buffer"

# prefix+e exports the newest buffer again.
tk_mark
printf 'explicit' | ti load-buffer -
tk_expect explicit "after-load-buffer hook" tk_osc52
tk_mark
tk_raw "${PREFIX}e"
tk_expect explicit "prefix+e" tk_osc52

# yo exports.
tk_mark
TMUX="$TK_TMUX" bash -c 'source "$DOTFILES_DIR/shell/tools/general.sh"; yo printf yo-output' >/dev/null
tk_expect yo-output "yo" tk_osc52

# Export has no off switch: a server whose old toggle was off exports again
# after a reload, and the toggle keys are gone.
ti set -g @clipboard-export off
ti source-file "$TK_CONFIG"
assert_eq "$(ti show -gqv @clipboard-export)" "" "reload kept the retired toggle"
assert_eq "$(ti list-keys -T prefix E 2>/dev/null)" "" "prefix+E still bound"
assert_eq "$(ti list-keys -T root S-F6 2>/dev/null)" "" "Shift+F6 still bound"
tk_mark
printf 'after reload' | ti load-buffer -
tk_expect 'after reload' "export after the toggle's retirement" tk_osc52

# Over @clipboard-limit: no clipboard, a message, the buffer still set.
ti set -g @clipboard-limit 10
tk_mark
select_line large
tk_raw y
tk_wait '#{pane_in_mode}' 0 test
assert_eq "$(ti show-buffer)" "large payload here" "over-limit copy sets the buffer"
tk_until tk_contains "clipboard skipped" tk_last_message || fail "no over-limit message: $(tk_last_message)"
expect_no_osc52 "over the limit"

printf 'tmux-clipboard: ok\n'
