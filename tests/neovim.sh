#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
[[ -n "$NVIM_BIN" ]] || { echo 'neovim: skipped (nvim unavailable)'; exit 0; }
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/bin/sh
printf 'called\n' >> "$DOTFILES_MUTATION_LOG"
exit 99
EOF
chmod +x "$TEST_ROOT/bin/curl"
export DOTFILES_MUTATION_LOG="$TEST_ROOT/network.log"
: > "$DOTFILES_MUTATION_LOG"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
export DOTFILES_THEME_ENABLED=0

printf 'markdown keeps two spaces  \n' > "$TEST_ROOT/note.md"
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
    "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" "$TEST_ROOT/note.md" '+write' '+quit'
grep -q '  $' "$TEST_ROOT/note.md" || fail "Markdown trailing spaces were removed"

printf 'python removes spaces   \nsecond line\n' > "$TEST_ROOT/code.py"
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
    "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" "$TEST_ROOT/code.py" \
        '+call cursor(2, 3)' '+let @/="needle"' '+write' \
        '+if line(".") != 2 || @/ !=# "needle" | cquit 31 | endif' '+quit'
grep -q '   $' "$TEST_ROOT/code.py" && fail "Python trailing spaces were retained"
[[ ! -s "$DOTFILES_MUTATION_LOG" ]] || fail "Neovim startup attempted a network download"

printf 'neovim: ok\n'
