#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
fixture_init
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
export DOTFILES_LEGACY_GENERATED_DIR="$TEST_ROOT/legacy"
export TEST_REAL_REPO="$ROOT" CALL_LOG="$TEST_ROOT/resolver-calls"
export DOTFILES_DIR="$TEST_ROOT/frontend"
mkdir -p "$DOTFILES_DIR/bin"
ln -s "$ROOT/shell" "$DOTFILES_DIR/shell"
cat > "$DOTFILES_DIR/bin/theme-switcher" <<'EOF'
#!/bin/bash
printf 'call\n' >> "$CALL_LOG"
export DOTFILES_DIR="$TEST_REAL_REPO"
exec "$TEST_REAL_REPO/bin/theme-switcher" "$@"
EOF
chmod +x "$DOTFILES_DIR/bin/theme-switcher"
export DOTFILES_TMUX_SERVER="dotfiles-refresh-$$"
trap 'tmux -L "$DOTFILES_TMUX_SERVER" kill-server 2>/dev/null || true; fixture_cleanup' EXIT

for shell in bash zsh; do
    export DOTFILES_TMUX_SERVER="dotfiles-refresh-$$-$shell"
    tmux -L "$DOTFILES_TMUX_SERVER" -f /dev/null new-session -d -s test
    export TEST_SESSION TEST_WINDOW TEST_OTHER_WINDOW
    TEST_SESSION="$(tmux -L "$DOTFILES_TMUX_SERVER" display-message -p '#{session_id}')"
    TEST_WINDOW="$(tmux -L "$DOTFILES_TMUX_SERVER" display-message -p '#{window_id}')"
    TEST_OTHER_WINDOW="$(tmux -L "$DOTFILES_TMUX_SERVER" new-window -d -P -F '#{window_id}')"
    if [[ "$shell" == bash ]]; then args=(--noprofile --norc -c); else args=(-dfc); fi
    "$shell" "${args[@]}" '
        theme() { "$DOTFILES_DIR/bin/theme-switcher" "$@"; }
        check() { "$@" || { printf "refresh assertion failed: %s\n" "$*" >&2; exit 1; }; }
        export TMUX=fixture
        theme set --global default gruvbox >/dev/null || exit 1
        source "$DOTFILES_DIR/shell/interactive/theme-env.sh"
        source "$DOTFILES_DIR/shell/theme-runtime.sh"
        : > "$CALL_LOG"
        false
        _dotfiles_theme_refresh
        check test "$?" = 1
        _dotfiles_theme_refresh
        check test ! -s "$CALL_LOG"
        check test "$DOTFILES_THEME_VIM_RESOLVED" = gruvbox

        theme set --global default everforest >/dev/null || exit 1
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = everforest
        theme set --session="$TEST_SESSION" default tokyo-night >/dev/null || exit 1
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = tokyo-night
        theme set --window="$TEST_WINDOW" vim kanagawa >/dev/null || exit 1
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = kanagawa
        tmux -L "$DOTFILES_TMUX_SERVER" select-window -t "$TEST_OTHER_WINDOW"
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = tokyo-night
        : > "$CALL_LOG"
        _dotfiles_theme_refresh
        check test ! -s "$CALL_LOG"

        # A standalone shell must ignore an unrelated running tmux server.
        export TMUX=""
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = everforest
        : > "$CALL_LOG"
        _dotfiles_theme_refresh
        check test ! -s "$CALL_LOG"

        theme disable >/dev/null || exit 1
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_ENABLED" = 0
        check test -z "${STARSHIP_CONFIG:-}${FZF_THEME_COLORS:-}"
        : > "$CALL_LOG"
        _dotfiles_theme_refresh
        check test ! -s "$CALL_LOG"
        theme enable >/dev/null || exit 1
        _dotfiles_theme_refresh
        check test "$DOTFILES_THEME_VIM_RESOLVED" = everforest

        # An unfamiliar schema must fall back to the validating resolver.
        printf "schema\t999\n" > "$XDG_STATE_HOME/dotfiles/preferences.tsv"
        : > "$CALL_LOG"
        _dotfiles_theme_refresh
        check test -s "$CALL_LOG"
        rm "$XDG_STATE_HOME/dotfiles/preferences.tsv"
    ' || fail "$shell theme refresh"
    tmux -L "$DOTFILES_TMUX_SERVER" kill-server
done
printf 'theme-refresh: ok\n'
