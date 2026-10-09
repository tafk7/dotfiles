#!/bin/bash
# Every tmux copy source reaches the tmux buffer and, while @clipboard-export is
# on, the client clipboard (OSC 52) through bin/tmux-copy.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

COPY='\e[2;5~'
PAUSE='\e[17;2~'
PREFIX='\001'

tk_start

# Prove an export did not happen: send a sentinel through the explicit path and
# require it to be the only payload since the mark.
expect_no_osc52() {
    sleep 0.3
    printf sentinel | TMUX="$TK_TMUX" "$DOTFILES_DIR/bin/tmux-copy" --always
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

# Pause turns automatic export off and shows the marker; the buffer is still set.
tk_raw "$PAUSE"
tk_wait '#{@clipboard-export}' off
tk_until tk_contains "CLIP OFF" tk_client_screen || fail "status bar shows no CLIP OFF marker"
tk_contains "clipboard export off" tk_last_message || fail "toggle message: $(tk_last_message)"
tk_mark
select_line alpha
tk_raw y
tk_wait '#{pane_in_mode}' 0 test
assert_eq "$(ti show-buffer)" "alpha beta" "y with export off"
printf 'hook off' | ti load-buffer -
expect_no_osc52 "export off"

# prefix+e exports regardless of the toggle.
tk_mark
printf 'explicit' | ti load-buffer -
tk_raw "${PREFIX}e"
tk_expect explicit "prefix+e with export off" tk_osc52

# yo exports regardless of the toggle.
tk_mark
TMUX="$TK_TMUX" bash -c 'source "$DOTFILES_DIR/shell/tools/general.sh"; yo printf yo-output' >/dev/null
tk_expect yo-output "yo with export off" tk_osc52

# A reload keeps the current value; prefix+E turns it back on.
ti source-file "$TK_CONFIG"
assert_eq "$(ti show -gv @clipboard-export)" off "reload reset the toggle"
tk_raw "${PREFIX}E"
tk_wait '#{@clipboard-export}' on
tk_until tk_lacks "CLIP OFF" tk_client_screen || fail "CLIP OFF marker stayed after turning export on"

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
