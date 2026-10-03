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

# An installed vim-plug is an autoload function: exists('*plug#begin') is false
# until the file is loaded. Provide a minimal fixture to prove init.vim calls
# the installed manager without downloading it.
mkdir -p "$XDG_CONFIG_HOME/nvim/autoload"
cat > "$XDG_CONFIG_HOME/nvim/autoload/plug.vim" <<'EOF'
function! plug#begin(...) abort
  let g:dotfiles_test_plug_begin = 1
  let g:dotfiles_test_plug_dir = a:1
  command! -nargs=+ Plug call plug#register(<q-args>)
endfunction
function! plug#register(...) abort
endfunction
function! plug#end(...) abort
endfunction
EOF

printf 'markdown keeps two spaces  \n' > "$TEST_ROOT/note.md"
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
    "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" "$TEST_ROOT/note.md" \
        '+if !get(g:, "dotfiles_test_plug_begin", 0) | cquit 30 | endif' \
        '+if g:dotfiles_test_plug_dir !=# stdpath("data") . "/plugged" | cquit 34 | endif' '+write' '+quit'
grep -q '  $' "$TEST_ROOT/note.md" || fail "Markdown trailing spaces were removed"

printf 'python removes spaces   \nsecond line\n' > "$TEST_ROOT/code.py"
mkdir -p "$XDG_CONFIG_HOME/nvim/plugged" "$XDG_CONFIG_HOME/nvim/undo"
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
    "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" "$TEST_ROOT/code.py" \
        '+call cursor(2, 3)' '+let @/="needle"' '+write' \
        '+if g:dotfiles_test_plug_dir !=# stdpath("config") . "/plugged" || &undodir !=# stdpath("config") . "/undo" | cquit 35 | endif' \
        '+if line(".") != 2 || @/ !=# "needle" | cquit 31 | endif' '+quit'
grep -q '   $' "$TEST_ROOT/code.py" && fail "Python trailing spaces were retained"
[[ ! -s "$DOTFILES_MUTATION_LOG" ]] || fail "Neovim startup attempted a network download"

# The palette colorscheme needs no plugins and never uses RGB, so tmux can map
# its colors to the window's theme.
theme_output="$(HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
    "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" \
        '+if get(g:, "colors_name", "") !=# "dotfiles" | cquit 32 | endif' \
        '+if &termguicolors | cquit 33 | endif' \
        '+if synIDattr(hlID("Comment"), "fg", "cterm") !=# "245" | cquit 36 | endif' \
        '+quit' 2>&1)" || fail "palette colorscheme did not load: $theme_output"
[[ "$theme_output" != *'E185'* ]] || fail "palette colorscheme emitted E185"

# A pin swaps the palette indices for one theme's RGB values; follow undoes it.
nvim_run() {
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" DOTFILES_DIR="$ROOT" PATH="$PATH" \
        "$NVIM_BIN" --headless -u "$ROOT/configs/init.vim" "$@" '+quit' 2>&1
}
bg_is() { printf '+if synIDattr(hlID("Normal"), "bg#", "gui") !=# "%s" | cquit %s | endif' "$1" "$2"; }
gruvbox_bg="$(source "$ROOT/themes/gruvbox.sh"; printf '%s' "$THEME_BG_HEX")"
light_bg="$(source "$ROOT/themes/github-light.sh"; printf '%s' "$THEME_BG_HEX")"
output="$(nvim_run '+Theme gruvbox' '+if !&termguicolors | cquit 37 | endif' "$(bg_is "$gruvbox_bg" 38)" \
    '+Theme follow' '+if &termguicolors | cquit 39 | endif')" || fail ":Theme pin and follow failed: $output"
"$ROOT/bin/theme-switcher" --nvim github-light >/dev/null
output="$(nvim_run "$(bg_is "$light_bg" 40)" '+if &background !=# "light" | cquit 41 | endif')" \
    || fail "saved Neovim pin was not applied: $output"
"$ROOT/bin/theme-switcher" --nvim follow >/dev/null
output="$(nvim_run '+if &termguicolors | cquit 42 | endif')" || fail "theme --nvim follow did not clear the pin: $output"

printf 'neovim: ok\n'
