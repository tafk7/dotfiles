#!/bin/bash
# bin/keys in the shell: the plain listing off a terminal, the pane-command
# mapping behind --here, the tmux popup on Alt+? and prefix+? (scoped to the
# pane's program, Ctrl+S widening it, Enter copying through OSC 52), the cache
# going stale when an input changes, and cheat as the old name.
set -euo pipefail
# shellcheck source=tests/lib/tmux-keys.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/tmux-keys.sh"

command -v nvim >/dev/null 2>&1 || { echo "keys: skipped (needs nvim)"; exit 0; }
tk_start
KEYS="$TK_CHECKOUT/bin/keys"
export NO_COLOR=1

# --- The index builds into this fixture's cache, and lists plainly off a terminal.
"$KEYS" build -o "$TEST_ROOT/viz" > "$TEST_ROOT/build.log" 2>&1 || fail "keys build: $(<"$TEST_ROOT/build.log")"
[[ -d "$XDG_CACHE_HOME/keys" && ! -e "$HOME/.cache/keys" ]] || fail "the cache is not under XDG_CACHE_HOME"
listing="$("$KEYS" -k alias)"
grep -qE '^ +gs +alias +Show working tree status' <<< "$listing" || fail "plain listing: $listing"
[[ "$listing" != *$'\e['* ]] || fail "color off a terminal"
[[ "$("$KEYS" ls -l tmux-prefix --tsv | cut -f1 | grep -c '^tmux-prefix:?$')" == 1 ]] || fail "prefix ? is not listed"

# --- --here: the pane's command names the program (copy mode wins).
assert_eq "$("$KEYS" _here codex 0)" codex "codex pane"
assert_eq "$("$KEYS" _here zsh 0)" shell "zsh pane"
assert_eq "$("$KEYS" _here bash 1)" copy "a pane in copy mode"
assert_eq "$("$KEYS" _here less 0)" "" "a program keys doesn't know"

# --- Stale: an edited input makes the cache stale; a build makes it fresh.
"$KEYS" _stale && fail "a fresh build reads as stale"
touch "$TK_CHECKOUT/configs/tmux.conf"
"$KEYS" _stale || fail "an edited tmux.conf left the cache fresh"
"$KEYS" build --cache-only >/dev/null
"$KEYS" _stale && fail "a rebuild left the cache stale"

# --- The popup: both keys open bin/keys scoped to the pane.
for key in "-T root M-?" "-T prefix ?"; do
    # shellcheck disable=SC2086  # table and key
    bound="$(ti list-keys $key)"
    [[ "$bound" == *run-shell*bin/keys*--popup*'#{pane_id}'*'#{client_name}'* ]] || fail "$key: $bound"
done
assert_eq "$(ti list-keys -N -P '' -T root M-? | sed 's/^ *//; s/  */ /')" "M-? Key lookup for this pane's program" "Alt+? note"

if command -v fzf >/dev/null 2>&1; then
    pane="$(ti new-window -t test -P -F '#{pane_id}' "$(tk_stub codex "$TEST_ROOT/codex.log")")"
    tk_ready "$TEST_ROOT/codex.log"
    tk_wait '#{pane_current_command}' codex "$pane"
    tk_raw '\e?'
    tk_until tk_contains 'keys ▸ codex >' tk_client_screen || fail "Alt+? popup: $(tk_client_screen)"
    tk_raw '\023'  # Ctrl+S: every program
    tk_until tk_contains 'keys > ' tk_client_screen || fail "Ctrl+S scope: $(tk_client_screen)"
    tk_raw 'alt+shift+j'
    tk_until tk_contains 'Yolo' tk_client_screen || fail "search: $(tk_client_screen)"
    tk_mark
    tk_raw '\r'
    tk_until tk_contains 'Alt+Shift+J' tk_osc52 || fail "Enter did not copy: $(tk_osc52)"
    tk_until tk_lacks 'keys >' tk_client_screen || fail "the popup stayed open"
    # prefix+? opens the same lookup.
    tk_raw '\001?'
    tk_until tk_contains 'keys ▸ codex >' tk_client_screen || fail "prefix+? popup: $(tk_client_screen)"
    tk_esc
    tk_until tk_lacks 'keys ▸' tk_client_screen || fail "Esc did not close the popup"
    [[ ! -s "$TEST_ROOT/codex.log" ]] || fail "keys typed into the pane behind the popup: $(tk_input "$TEST_ROOT/codex.log")"
else
    echo "keys: popup checks skipped (needs fzf)"
fi

# --- cheat is keys.
grep -q "^alias cheat='\$DOTFILES_DIR/bin/keys'" "$TK_CHECKOUT/shell/tools/general.sh" || fail "cheat is not keys"

printf 'keys: ok\n'
