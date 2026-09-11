#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'tmux -L dotfiles-theme-tests kill-server 2>/dev/null || true; rm -rf "$TMP_ROOT"' EXIT

export DOTFILES_DIR="$ROOT"
export DOTFILES_GENERATED_DIR="$TMP_ROOT/generated"
export DOTFILES_LEGACY_GENERATED_DIR="$TMP_ROOT/legacy-generated"
export DOTFILES_TMUX_SERVER=dotfiles-theme-tests
export TMUX_TMPDIR="$TMP_ROOT/tmux"
export HOME="$TMP_ROOT/home"
export TMUX=
mkdir -p "$TMUX_TMPDIR" "$HOME" "$DOTFILES_LEGACY_GENERATED_DIR"
printf 'export DOTFILES_THEME="gruvbox"\n_DOTFILES_PREVIOUS_THEME="nord"\n' > "$DOTFILES_LEGACY_GENERATED_DIR/theme.sh"
printf 'export DOTFILES_THEME=gruvbox\nexport DOTFILES_THEME_PREVIOUS=nord\nexport DOTFILES_THEME_GENERATION=42\nexport DOTFILES_THEME_CODE=catppuccin\n' \
    > "$DOTFILES_LEGACY_GENERATED_DIR/theme-state.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"; }
theme() { "$ROOT/bin/theme-switcher" "$@"; }
t() { tmux -L "$DOTFILES_TMUX_SERVER" "$@"; }

# Standalone/global compatibility and precedence.
theme --init
assert_eq "$(theme resolve vim --global)" catppuccin "legacy global override migration"
theme unset code >/dev/null
theme tokyo-night >/dev/null
theme --revert >/dev/null
assert_eq "$(theme resolve tmux --global)" gruvbox "global revert compatibility"
theme tokyo-night >/dev/null
theme set code catppuccin >/dev/null
theme set vim gruvbox >/dev/null
assert_eq "$(theme resolve vim --global)" gruvbox "global tool beats group"
assert_eq "$(theme resolve bat --global)" catppuccin "global group beats default"
assert_eq "$(theme resolve tmux --global)" tokyo-night "global fallback"
theme unset vim >/dev/null
assert_eq "$(theme resolve vim --global)" catppuccin "clear restores group"
theme reset >/dev/null
assert_eq "$(theme resolve vim --global)" tokyo-night "legacy reset clears overrides"

relocated="$TMP_ROOT/relocated dotfiles"
cp -a "$ROOT" "$relocated"
assert_eq "$(DOTFILES_DIR="$relocated" "$relocated/bin/theme-switcher" resolve vim --global)" \
    tokyo-night "repository relocation lost durable theme state"

# A running interactive shell refreshes exports and FZF options from the
# generation signature without manual variable-by-variable exports.
# env-runtime.sh resolves the theme for interactive shells only; this test
# harness is a non-interactive script, so opt back in explicitly.
export DOTFILES_FORCE_THEME_ENV=1
source "$ROOT/shell/env-runtime.sh"
source "$ROOT/shell/fzf.sh"
source "$ROOT/shell/theme-runtime.sh"
theme github-light >/dev/null
_dotfiles_theme_refresh
assert_eq "$DOTFILES_THEME_VIM_RESOLVED" github-light "prompt refresh"
[[ "$FZF_DEFAULT_OPTS" == *'bg:#ffffff'* ]] || fail "FZF options did not refresh"
theme tokyo-night >/dev/null
_dotfiles_theme_refresh

# Isolated tmux server: two sessions and three independent windows.
t -f /dev/null new-session -d -s alpha -n one
t new-window -d -t alpha -n two
t new-session -d -s beta -n three
sid_a="$(t display-message -p -t alpha '#{session_id}')"
sid_b="$(t display-message -p -t beta '#{session_id}')"
wid_one="$(t display-message -p -t alpha:one '#{window_id}')"
wid_two="$(t display-message -p -t alpha:two '#{window_id}')"
wid_three="$(t display-message -p -t beta:three '#{window_id}')"

theme set --session="$sid_a" default catppuccin >/dev/null
theme set --session="$sid_b" default github-light >/dev/null
theme set -s="$sid_a" fzf kanagawa >/dev/null
assert_eq "$(theme resolve fzf --window="$wid_one")" kanagawa "short session scope"
theme set --window="$wid_two" default everforest >/dev/null
theme set -w="$wid_two" lazygit vesper >/dev/null
assert_eq "$(theme resolve lazygit --window="$wid_two")" vesper "short window scope"
theme set --window="$wid_two" vim gruvbox >/dev/null
theme set --window="$wid_two" tmux catppuccin >/dev/null

# Global switching recomputes inherited windows while preserving every scoped
# value already attached to a session/window.
theme set default kanagawa >/dev/null

assert_eq "$(theme resolve bat --window="$wid_two")" everforest "window default masks session"
assert_eq "$(theme resolve vim --window="$wid_two")" gruvbox "window tool beats default"
assert_eq "$(theme resolve tmux --window="$wid_two")" catppuccin "independent tmux tool"
assert_eq "$(theme resolve vim --window="$wid_one")" catppuccin "session inheritance"
assert_eq "$(theme resolve vim --window="$wid_three")" github-light "session isolation"
assert_eq "$(t show-options -qv -w -t "$wid_two" @dotfiles_theme_effective)" catppuccin
assert_eq "$(t show-options -qv -w -t "$wid_three" @dotfiles_theme_effective)" github-light
assert_eq "$(t show-options -qv -w -t "$wid_three" 'pane-colours[15]')" '#24292f' "light ANSI palette"

# Older tmux keeps scoped canvas colors but records the ANSI limitation rather
# than attempting a terminal-global OSC palette mutation.
t new-window -d -t "$sid_b" -n legacy-palette
wid_legacy="$(t display-message -p -t "$sid_b":legacy-palette '#{window_id}')"
DOTFILES_TMUX_VERSION=3.2 "$ROOT/bin/theme-switcher" tmux-sync-window "$wid_legacy" "$sid_b" >/dev/null
assert_eq "$(t show-options -qv -w -t "$wid_legacy" @dotfiles_theme_palette)" unavailable
assert_eq "$(t show-options -qv -w -t "$wid_legacy" window-style)" 'bg=#ffffff,fg=#24292f'

# Representative inverse combinations: a light window in a dark session and a
# dark window in a light session.
t new-window -d -t "$sid_a" -n light-window
wid_light="$(t display-message -p -t "$sid_a":light-window '#{window_id}')"
theme set --window="$wid_light" default github-light >/dev/null
t new-window -d -t "$sid_b" -n dark-window
wid_dark="$(t display-message -p -t "$sid_b":dark-window '#{window_id}')"
theme set --window="$wid_dark" default vesper >/dev/null
assert_eq "$(theme resolve bat --window="$wid_light")" github-light
assert_eq "$(theme resolve bat --window="$wid_dark")" vesper
theme tmux-sync-status "$sid_a" "$wid_light"
assert_eq "$(t show-options -qv -t "$sid_a" status-style)" 'bg=#ffffff,fg=#24292f' "status follows selected window theme"

# Two control-mode clients can attach to one session while the status values
# remain session/window data rather than terminal-global palette state.
# shellcheck disable=SC2016
timeout 3s bash -c 'tail -f /dev/null | tmux -L "$DOTFILES_TMUX_SERVER" -C attach-session -t "$1"' _ "$sid_a" >"$TMP_ROOT/client1" 2>&1 &
client1=$!
# shellcheck disable=SC2016
timeout 3s bash -c 'tail -f /dev/null | tmux -L "$DOTFILES_TMUX_SERVER" -C attach-session -t "$1"' _ "$sid_a" >"$TMP_ROOT/client2" 2>&1 &
client2=$!
for _ in {1..20}; do
    clients="$(t list-clients -t "$sid_a" -F '#{client_name}' 2>/dev/null | wc -l)"
    (( clients >= 2 )) && break
    sleep 0.05
done
(( clients >= 2 )) || fail "two clients did not attach to one session"
kill "$client1" "$client2" 2>/dev/null || true

# Shell/tool launch state follows the same window without shared active files.
env_out="$(theme env --window="$wid_two")"
eval "$env_out"
assert_eq "$DOTFILES_THEME_VIM_RESOLVED" gruvbox
assert_eq "$DOTFILES_THEME_TMUX_RESOLVED" catppuccin
assert_eq "$DOTFILES_THEME_BTOP_RESOLVED" everforest
[[ "$STARSHIP_CONFIG" == */themes/everforest/starship.toml ]] || fail "scoped Starship path"
[[ "$LAZYGIT_THEME_CONFIG" == */themes/vesper/lazygit.yml ]] || fail "scoped lazygit path"
assert_eq "$DELTA_FEATURES" everforest

# Clear/reset restore inheritance without touching another session.
theme clear --window="$wid_two" tmux >/dev/null
assert_eq "$(theme resolve tmux --window="$wid_two")" everforest
theme reset --window="$wid_two" >/dev/null
assert_eq "$(theme resolve vim --window="$wid_two")" catppuccin
assert_eq "$(theme resolve vim --window="$wid_three")" github-light

# Stable ids survive renames and index changes.
t rename-session -t "$sid_a" renamed
t rename-window -t "$wid_one" renamed-window
assert_eq "$(theme resolve vim --window="$wid_one")" catppuccin "renames"

# Moving an unoverridden window changes the session it inherits from.
t move-window -s "$wid_one" -t "$sid_b":9
theme tmux-sync >/dev/null
assert_eq "$(theme resolve vim --window="$wid_one")" github-light "move changes owner session"

# A linked window has one canvas. Its deterministic owner is the lowest stable
# session id, so clients cannot race conflicting session palettes onto it.
t link-window -s "$wid_three" -t "$sid_a":8
theme tmux-sync >/dev/null
owner="$(printf '%s\n%s\n' "$sid_a" "$sid_b" | sort -t'$' -k2,2n | head -1)"
expected=catppuccin; [[ "$owner" == "$sid_b" ]] && expected=github-light
assert_eq "$(theme resolve vim --window="$wid_three")" "$expected" "linked-window owner"
linked="$(theme explain --window="$wid_three")"
[[ "$linked" == *"linked:"* ]] || fail "linked-window explanation"

# New windows and splits inherit after the same hook target used by tmux.conf.
t new-window -d -t "$sid_a" -n fresh
wid_fresh="$(t display-message -p -t "$sid_a":fresh '#{window_id}')"
theme tmux-sync-window "$wid_fresh" "$sid_a" >/dev/null
assert_eq "$(t show-options -qv -w -t "$wid_fresh" @dotfiles_theme_effective)" catppuccin
t split-window -d -t "$wid_fresh"
assert_eq "$(t show-options -Aqv -p -t "$wid_fresh".1 'pane-colours[1]')" '#f38ba8' "split inherits palette"

# Pane tint tracks the effective tmux theme and is recomputed on theme changes.
pane="$(t display-message -p -t "$wid_fresh".0 '#{pane_id}')"
theme tint 2 "$pane"
assert_eq "$(t show-options -qv -p -t "$pane" @dotfiles_pane_tint)" 2
theme set --window="$wid_fresh" tmux github-light >/dev/null
assert_eq "$(t show-options -qv -p -t "$pane" window-style)" 'bg=#EAEEF2,fg=#24292f'

diagnostic="$(TMUX=isolated theme diagnose)"
[[ "$diagnostic" == *'ANSI:'* && "$diagnostic" == *'Truecolor:'* && "$diagnostic" == *'tmux palette: scoped'* ]] \
    || fail "diagnostic must exercise default, ANSI, truecolor, and scoped palette paths"

# Multiple-client safety is represented by format-driven status values: tmux
# expands the selected window's local options independently for each client.
theme tmux-configure
hooks="$(t show-hooks -g after-select-window)"
[[ "$hooks" == *'after-select-window[90]'* ]] || fail "selected-window status hook missing"
left_a="$(t display-message -p -t "$wid_fresh" '#{E:@dotfiles_status_left}')"
left_b="$(t display-message -p -t "$wid_three" '#{E:@dotfiles_status_left}')"
[[ "$left_a" != "$left_b" ]] || fail "window-local status palettes should differ"

# Disable removes live hooks/styles but preserves scope choices for a reversible
# re-enable. This is the explicit live migration path used at Gate B.
theme disable >/dev/null
if t show-hooks -g after-select-window | grep -Fq 'after-select-window[90]'; then
    fail "theme disable left the selected-window hook wired"
fi
assert_eq "$(t show-options -qv -w -t "$wid_fresh" @dotfiles_theme_tmux)" github-light "disable removed window preference"
theme enable >/dev/null
assert_eq "$(theme resolve tmux --window="$wid_fresh")" github-light "re-enable lost window preference"

printf 'theme-system: ok\n'
