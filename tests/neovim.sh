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
# Plugin install hooks run downloads outside the pins; the fzf plugin's would
# fetch an unverified fzf whenever the eget pin differs from its version.
if grep -E "^[[:space:]]*Plug .*'do'" "$ROOT/configs/init.vim"; then
    fail "a Neovim plugin declares a post-install hook"
fi

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
# Its keys are tmux review's: Shift+PgUp/PgDn scroll three lines, / searches
# upward, y copies and closes, Esc closes, Ctrl+E/D jump between prompts.
output="$(NVIM_REVIEW=1 nvim_run \
    '+if maparg("<S-PageUp>", "n") !=# "3<C-Y>" || maparg("<S-PageDown>", "x") !=# "3<C-E>" | cquit 50 | endif' \
    '+if maparg("/", "n") !=# "?" || maparg("y", "x") !~# "+y.*qall" || maparg("<Esc>", "n") !~# "qall" | cquit 46 | endif')" \
    || fail "review keys: $output"
printf 'start\n## User\nalpha\n## User\nbeta\n' > "$TEST_ROOT/review.md"
output="$(NVIM_REVIEW=1 NVIM_REVIEW_PROMPT='^## User' nvim_run "$TEST_ROOT/review.md" '+normal! G' \
    "+call feedkeys(\"\\<C-e>\", 'xt')" '+if line(".") != 4 | cquit 47 | endif' \
    "+call feedkeys(\"\\<C-e>\", 'xt')" '+if line(".") != 2 | cquit 48 | endif' \
    "+call feedkeys(\"\\<C-d>\", 'xt')" '+if line(".") != 4 | cquit 49 | endif')" \
    || fail "review prompt jumps: $output"
# Shift selects as it moves and a plain move drops the selection; h starts one
# that plain moves extend, until h. Each scenario runs in one feedkeys call,
# whose end leaves Visual mode; P() records mode, line and column on the way.
printf 'start\n## User\nalpha beta gamma\n## User\nbeta\nlast line here\n' > "$TEST_ROOT/select.md"
cat > "$TEST_ROOT/select.vim" <<'VIM'
let g:seen = []
function! P() abort
  call add(g:seen, mode() . line('.') . ':' . col('.'))
  return ''
endfunction
let s:fail = []
function! s:run(name, line, col, keys, want) abort
  let g:seen = []
  call cursor(a:line, a:col)
  call feedkeys(substitute(a:keys, '|', "\<Cmd>call P()\<CR>", 'g'), 'xt')
  if g:seen !=# a:want
    call add(s:fail, a:name . ': got ' . string(g:seen) . ' want ' . string(a:want))
  endif
  execute "normal! \<Esc>"
endfunction
call s:run('Shift selects, plain drops', 3, 1, "F|F|d|", ['v3:2', 'v3:3', 'n4:3'])
call s:run('h toggles', 3, 1, "h|ff|d|h|", ['v3:1', 'v3:3', 'v4:3', 'n4:3'])
call s:run('Shift+arrow, then arrow', 3, 1, "\<S-Right>|\<Right>|", ['v3:2', 'n3:3'])
call s:run('Ctrl+Shift prompt jumps', 5, 1, "\<C-S-e>|\<C-S-e>|\<C-d>|", ['v4:1', 'v2:1', 'n4:1'])
call s:run('Ctrl+Shift word, Esc, Shift+End', 3, 1, "\<C-S-f>|\<Esc>|\<S-End>|", ['v3:5', 'n3:5', 'v3:16'])
call s:run('s and e move', 3, 5, "s|e|", ['n3:4', 'n2:4'])
call s:run('Ctrl+Shift+End', 3, 1, "\<C-S-End>|", ['v6:1'])
if !empty(s:fail) | call writefile(s:fail, '/dev/stderr') | cquit 51 | endif
VIM
output="$(NVIM_REVIEW=1 NVIM_REVIEW_PROMPT='^## User' nvim_run "$TEST_ROOT/select.md" "+source $TEST_ROOT/select.vim")" \
    || fail "review selection keys: $output"

# Alt+Backspace / Alt+Delete delete to the line's start / end in insert mode;
# Ctrl+Z undoes in insert, normal, and visual mode, and Ctrl+U deletes to the
# line's start in insert mode, as in the shells.
printf 'hello brave world\n' > "$TEST_ROOT/keys.md"
line_after() {
    nvim_run "$TEST_ROOT/keys.md" "+call cursor(1, $1)" "+call feedkeys(\"$2\", 'xt')" \
        "+if getline(1) !=# '$3' | cquit 60 | endif" '+qall!' >/dev/null || fail "keys $2: expected '$3'"
}
line_after 7 'i\<M-BS>\<Esc>' 'brave world'
line_after 7 'i\<M-Del>\<Esc>' 'hello '
line_after 1 'A typed\<C-z>\<Esc>' 'hello brave world'
line_after 1 'A one\<Esc>A two\<Esc>\<C-z>' 'hello brave world one'
line_after 1 'A one\<Esc>v\<C-z>' 'hello brave world'
line_after 13 'i\<C-u>\<Esc>' 'world'
# Ctrl+Backspace (Ctrl+H through tmux) and Ctrl+Delete delete a word, to the
# word's end as the shells' kill-word does.
line_after 7 'i\<C-h>\<Esc>' 'brave world'
line_after 7 'i\<C-BS>\<Esc>' 'brave world'
line_after 7 'i\<C-Del>\<Esc>' 'hello  world'
line_after 11 'i\<C-Del>\<Esc>' 'hello brav world'
# Shift+PgUp/PgDn scroll three lines outside tmux, as in review.
output="$(nvim_run '+if maparg("<S-PageUp>", "n") !~# "ScrollLines" || maparg("<S-Up>", "n") !=# "" | cquit 61 | endif')" \
    || fail "Shift+PgUp scroll: $output"

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
