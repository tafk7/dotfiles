#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
export DOTFILES_DIR="$ROOT"
export DOTFILES_TMUX_SERVER=dotfiles-theme-tests
unset DOTFILES_STATE_DIR DOTFILES_TMUX_VERSION
trap 'tmux -L "$DOTFILES_TMUX_SERVER" kill-server 2>/dev/null || true; fixture_cleanup' EXIT

theme() { "$ROOT/bin/theme-switcher" "$@"; }
t() { tmux -L "$DOTFILES_TMUX_SERVER" "$@"; }
# A format as tmux expands it for a window or pane, including inherited options.
expand() { t display-message -p -t "$1" "$2"; }
palette() { (source "$ROOT/themes/$1.sh"; eval "printf '%s\n' \"\${$2}\""); }

t -f "$ROOT/configs/tmux.conf" new-session -d -s alpha -x 120 -y 30
theme tmux-init
w1="$(t display-message -p -t alpha: '#{window_id}')"

# Default global theme; styles resolve through the @theme_* options.
assert_eq "$(expand "$w1" '#{@theme}')" gruvbox "default global theme"
assert_eq "$(expand "$w1" '#{E:window-style}')" "bg=$(palette gruvbox THEME_BG_HEX),fg=$(palette gruvbox THEME_FG_HEX)" "window canvas"
assert_eq "$(t show-options -gwv 'pane-colours[1]')" "$(palette gruvbox 'THEME_ANSI[1]')" "global ANSI palette"
assert_eq "$(t show-options -gwv 'pane-colours[245]')" "$(palette gruvbox THEME_SECONDARY_HEX)" "secondary role slot"

# Global changes persist and reach every window that has no override.
theme kanagawa >/dev/null
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "global switch"
assert_eq "$(awk -F '\t' '$1 == "default" { print $2 }' "$XDG_STATE_HOME/dotfiles/theme.tsv")" kanagawa "persisted global"

# New windows inherit without hooks.
w2="$(t new-window -d -P -F '#{window_id}' -t alpha:)"
assert_eq "$(expand "$w2" '#{@theme}')" kanagawa "new window inherits global"

# A window override changes only that window, including its status bar.
theme --window="$w2" vesper >/dev/null
assert_eq "$(expand "$w2" '#{@theme}')" vesper "window override"
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "other windows keep the global theme"
assert_eq "$(expand "$w2" '#{E:status-style}')" "bg=$(palette vesper THEME_BG_HEX),fg=$(palette vesper THEME_FG_HEX)" "status follows the window"
assert_eq "$(t show-options -wv -t "$w2" 'pane-colours[1]')" "$(palette vesper 'THEME_ANSI[1]')" "window ANSI palette"

split="$(t split-window -d -P -F '#{pane_id}' -t "$w2")"
assert_eq "$(expand "$split" '#{@theme}')" vesper "split inherits the window theme"
assert_eq "$(t show-options -Aqv -p -t "$split" 'pane-colours[1]')" "$(palette vesper 'THEME_ANSI[1]')" "split inherits the palette"

# A global change leaves the override alone.
theme tokyo-night >/dev/null
assert_eq "$(expand "$w2" '#{@theme}')" vesper "override survives a global change"
assert_eq "$(expand "$w1" '#{@theme}')" tokyo-night "global change"

# Pane tints are formats, so they follow later theme changes.
theme tint 2 "$split"
assert_eq "$(expand "$split" '#{E:window-style}')" "bg=$(palette vesper THEME_TINT_2),fg=$(palette vesper THEME_FG_HEX)" "tint"
theme --window="$w2" github-light >/dev/null
assert_eq "$(expand "$split" '#{E:window-style}')" "bg=$(palette github-light THEME_TINT_2),fg=$(palette github-light THEME_FG_HEX)" "tint follows the theme"
theme tint 0 "$split"
assert_eq "$(expand "$split" '#{E:window-style}')" "bg=$(palette github-light THEME_BG_HEX),fg=$(palette github-light THEME_FG_HEX)" "tint reset"

# Clearing returns the window to the global theme.
theme --window="$w2" clear >/dev/null
assert_eq "$(expand "$w2" '#{@theme}')" tokyo-night "cleared window follows global"
assert_eq "$(t show-options -qwv -t "$w2" 'pane-colours[1]')" "" "cleared window palette"

theme --revert >/dev/null
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "revert"

# Unknown names and window ids fail without changing anything.
theme no-such-theme >/dev/null 2>&1 && fail "unknown theme accepted"
theme --window=@999 vesper >/dev/null 2>&1 && fail "unknown window accepted"
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "failed switch changed the theme"

# tmux before 3.3 has no pane-colours: styles still apply, the palette is skipped.
t set-option -u -gw pane-colours
DOTFILES_TMUX_VERSION=3.2 theme tmux-init
assert_eq "$(t show-options -gwv 'pane-colours[1]' 2>/dev/null || true)" "" "pre-3.3 palette"
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "pre-3.3 styles"
theme tmux-init

# Disabling resets every color to the terminal default and drops overrides.
theme --window="$w2" vesper >/dev/null
theme disable >/dev/null
assert_eq "$(expand "$w1" '#{E:window-style}')" "bg=default,fg=default" "disabled canvas"
assert_eq "$(expand "$w2" '#{@theme}')" off "disable clears window overrides"
assert_eq "$(t show-options -gwv 'pane-colours[1]' 2>/dev/null || true)" "" "disabled palette"
theme kanagawa >/dev/null 2>&1 && fail "disabled feature accepted a theme"
theme enable >/dev/null
assert_eq "$(expand "$w1" '#{@theme}')" kanagawa "enable restores the global theme"

# Every theme applies cleanly.
for file in "$ROOT"/themes/*.sh; do
    name="$(basename "$file" .sh)"
    theme --window="$w1" "$name" >/dev/null
    assert_eq "$(expand "$w1" '#{@theme}')" "$name" "apply $name"
done

printf 'theme-system: ok\n'
