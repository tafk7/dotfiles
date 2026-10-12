#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
REAL_HARPER="$(command -v harper-ls 2>/dev/null || true)"
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

# The review profile loads only in the tmux review popup.
output="$(nvim_run '+if maparg("e", "n") !=# "" | cquit 43 | endif')" || fail "review mappings leaked into plain nvim: $output"
output="$(NVIM_REVIEW=1 nvim_run '+if maparg("e", "n") !=# "k" || maparg("q", "n") !~# "qall" | cquit 44 | endif')" \
    || fail "review profile did not load: $output"

# The prose profile loads only in the compose pane; its send keys only with a
# target pane; grammar only when harper-ls is installed and nvim has
# vim.lsp.enable (0.11+).
output="$(nvim_run '+if &spell || maparg("<C-l>", "i") !=# "" | cquit 45 | endif')" \
    || fail "prose settings leaked into plain nvim: $output"
printf 'draft\n' > "$TEST_ROOT/draft.md"
output="$(NVIM_PROSE=1 nvim_run "$TEST_ROOT/draft.md" \
    '+if !&spell || &filetype !=# "markdown" || maparg("<C-l>", "i") ==# "" | cquit 46 | endif' \
    '+if get(maparg("<C-s>", "i", 0, 1), "buffer", 0) | cquit 47 | endif')" || fail "prose profile without a target: $output"
output="$(NVIM_PROSE=1 DOTFILES_COMPOSE_TARGET=%1 nvim_run "$TEST_ROOT/draft.md" \
    '+if !get(maparg("<C-s>", "i", 0, 1), "buffer", 0) || !get(maparg("<C-s>", "n", 0, 1), "buffer", 0) | cquit 48 | endif' \
    '+if !get(maparg("<C-S-s>", "i", 0, 1), "buffer", 0) | cquit 50 | endif')" \
    || fail "compose keys missing with a target: $output"
lsp_check='+lua if vim.lsp.enable and vim.lsp.is_enabled("harper_ls") ~= (vim.env.EXPECT == "1") then vim.cmd("cquit 49") end'
output="$(NVIM_PROSE=1 EXPECT=0 nvim_run "$lsp_check")" || fail "harper enabled without the binary: $output"
printf '#!/bin/sh\nexit 0\n' > "$TEST_ROOT/bin/harper-ls"
chmod +x "$TEST_ROOT/bin/harper-ls"
output="$(NVIM_PROSE=1 EXPECT=1 nvim_run "$lsp_check")" || fail "harper not enabled with the binary: $output"
rm -f "$TEST_ROOT/bin/harper-ls"

# Ctrl+L fixes the last problem before the cursor and leaves the cursor where
# the typing was. Without harper-ls: Vim's first spelling suggestion.
printf 'I saw teh\n' > "$TEST_ROOT/typo.md"
output="$(NVIM_PROSE=1 nvim_run "$TEST_ROOT/typo.md" '+call feedkeys("A\<C-l>X\<Esc>", "xt")' \
    '+if getline(1) !=# "I saw theX" | cquit 51 | endif' '+qall!')" || fail "Ctrl+L spelling fallback: $output"
# With harper-ls (when installed here): its grammar fix, then the next one back.
if [[ -n "$REAL_HARPER" ]] && nvim_run '+lua if not vim.lsp.enable then vim.cmd("cquit 1") end' >/dev/null; then
    ln -s "$REAL_HARPER" "$TEST_ROOT/bin/harper-ls"
    printf 'This is an test of teh checker\n' > "$TEST_ROOT/grammar.md"
    output="$(NVIM_PROSE=1 nvim_run "$TEST_ROOT/grammar.md" \
        '+lua vim.wait(10000, function() return #vim.diagnostic.get(0) >= 2 end, 100)' \
        '+call feedkeys("A\<C-l>\<C-l>X\<Esc>", "xt")' \
        '+if getline(1) !=# "This is a test of the checkerX" | cquit 52 | endif' '+qall!')" || fail "Ctrl+L with Harper: $output"
    rm -f "$TEST_ROOT/bin/harper-ls"
fi

printf 'neovim: ok\n'
