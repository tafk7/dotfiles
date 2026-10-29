" Neovim configuration (dotfiles)

" ==============================================================================
" Plugins
" ==============================================================================

" The dev tier installs vim-plug and these plugins at their pinned commits
" (bin/install-editor-plugins, Neovim's configure step); editor startup never
" downloads or executes remote code. No linter plugin: one that runs a
" project's own tools on edit runs code from every checkout opened.

let s:vim_plug = stdpath('config') . '/autoload/plug.vim'
if filereadable(s:vim_plug)
execute 'source ' . fnameescape(s:vim_plug)
" Preserve existing installations; new profiles use the XDG data directory.
let s:plug_dir = isdirectory(stdpath('config') . '/plugged')
      \ ? stdpath('config') . '/plugged' : stdpath('data') . '/plugged'
call plug#begin(s:plug_dir)
unlet s:plug_dir

" Essential tpope plugins
Plug 'tpope/vim-fugitive', { 'commit': '3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0' }
Plug 'tpope/vim-surround', { 'commit': '3d188ed2113431cf8dac77be61b842acb64433d9' }
Plug 'tpope/vim-commentary', { 'commit': '64a654ef4a20db1727938338310209b6a63f60c9' }
Plug 'tpope/vim-repeat', { 'commit': '65846025c15494983dafe5e3b46c8f88ab2e9635' }
Plug 'tpope/vim-unimpaired', { 'commit': 'db65482581a28e4ccf355be297f1864a4e66985c' }

" File navigation. No fzf#install() hook: when the fzf on PATH (the eget pin)
" differs from the plugin's own version, it downloads an unverified binary
" into the plugin, which fzf.vim then prefers. The plugin uses the PATH fzf.
Plug 'junegunn/fzf', { 'commit': 'b224480a98a40c670c8ed89abd52d4216a470032' }
Plug 'junegunn/fzf.vim', { 'commit': '023de3c0e158ff9c2b0992175af10be97c2f2158' }

" Git integration
Plug 'airblade/vim-gitgutter', { 'commit': '90b75207bd9b55d8ac4af15f72b4e935462014d0' }

" Editing enhancements
Plug 'jiangmiao/auto-pairs', { 'commit': '39f06b873a8449af8ff6a3eee716d3da14d63a76' }

" UI enhancements
Plug 'vim-airline/vim-airline', { 'commit': 'ae24f4aca06731d5d7224df1fc5415975331b214' }
Plug 'vim-airline/vim-airline-themes', { 'commit': '77aab8c6cf7179ddb8a05741da7e358a86b2c3ab' }
Plug 'machakann/vim-highlightedyank', { 'commit': '285a61425e79742997bbde76a91be6189bc988fb' }

" Syntax and language support
Plug 'sheerun/vim-polyglot', { 'commit': 'f061eddb7cdcc614c8406847b2bfb53099832a4e' }

call plug#end()
endif
unlet s:vim_plug

" ==============================================================================
" Basic Settings
" ==============================================================================

set nocompatible

set encoding=utf-8
setglobal fileencoding=utf-8

filetype plugin indent on

syntax enable

" ==============================================================================
" Visual Settings
" ==============================================================================

if &term =~ '256color'
    " Disable Background Color Erase (BCE)
    set t_ut=
endif

" Palette colors, not RGB: tmux maps them to the window's theme, so the editor
" follows `theme` changes while it runs (see configs/nvim/colors/dotfiles.vim).
" `:Theme NAME` pins this editor to one theme instead; `theme --nvim NAME` pins
" every new editor (see docs/theme-system.md).
set notermguicolors
if exists('$DOTFILES_DIR') && isdirectory($DOTFILES_DIR . '/configs/nvim')
    execute 'set runtimepath^=' . fnameescape($DOTFILES_DIR . '/configs/nvim')
    let g:dotfiles_nvim_theme = dotfiles#theme#saved()
    command! -nargs=? -complete=customlist,dotfiles#theme#complete Theme call dotfiles#theme#set(<q-args>)
    silent! colorscheme dotfiles
endif

set number

set cursorline

set showmatch

set laststatus=2

set showcmd

set wildmenu
set wildmode=longest:full,full
set wildignorecase

" Redraw only when needed (faster macros)
set lazyredraw

" ==============================================================================
" Search Settings
" ==============================================================================

set hlsearch

set incsearch

set ignorecase

set smartcase

" Clear search highlighting with Space
nnoremap <silent> <Space> :nohlsearch<CR>

" ==============================================================================
" Indentation and Formatting
" ==============================================================================

set expandtab

set tabstop=4
set softtabstop=4
set shiftwidth=4

set autoindent
set smartindent

set linebreak

" Don't wrap lines by default
set nowrap

set list
set listchars=tab:▸\ ,trail:·,extends:❯,precedes:❮,nbsp:×

" ==============================================================================
" Mouse and Clipboard
" ==============================================================================

if has('mouse')
    set mouse=a
    if !has('nvim')
        set ttymouse=xterm2
    endif
endif

if has('clipboard')
    if has('unnamedplus')
        set clipboard=unnamedplus
    else
        set clipboard=unnamed
    endif
endif

" ==============================================================================
" File Management
" ==============================================================================

set noswapfile

set nobackup
set nowritebackup

if has('persistent_undo')
    set undofile
    let &undodir = isdirectory(stdpath('config') . '/undo')
          \ ? stdpath('config') . '/undo' : stdpath('state') . '/undo'
    if !isdirectory(&undodir)
        call mkdir(&undodir, 'p')
    endif
endif

set autoread

set path+=**

" ==============================================================================
" Window Management
" ==============================================================================

set splitright
set splitbelow

set winminheight=0

" ==============================================================================
" Key Mappings
" ==============================================================================

let mapleader = ","
let g:mapleader = ","

" File operations
nnoremap <leader>w :w!<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>

" Better escape (keep both Esc and jk)
inoremap jk <Esc>

" Line deletes match the shells and Codex: Alt+Backspace to the start of the
" line, Alt+Delete to the end. Ctrl+U keeps Neovim's meaning, which in insert
" mode is the same delete, as in the shells and agents.
inoremap <M-BS> <C-g>u<C-u>
inoremap <M-Del> <C-g>u<Cmd>call setline('.', strpart(getline('.'), 0, col('.') - 1))<CR>
cnoremap <M-BS> <C-u>
cnoremap <M-Del> <Cmd>call setcmdline(strpart(getcmdline(), 0, getcmdpos() - 1))<CR>

" Ctrl+Z undoes in every mode, as in the shells, the agents and Windows, and
" never suspends (configs/tmux.conf); in visual mode it leaves the selection
" first.
inoremap <C-z> <C-g>u<Cmd>undo<CR>
nnoremap <C-z> u
xnoremap <C-z> <Esc>u

" Word deletes match them too: Ctrl+Backspace and Ctrl+Delete take a word.
" tmux hands Ctrl+Backspace on as Ctrl+H, which Neovim would read as one
" Backspace; the Backspace key itself sends DEL, so Ctrl+H is free to take
" (auto-pairs would map it as Backspace otherwise). Ctrl+Delete deletes to the
" end of the word, as the shells' kill-word does; with no word left on the
" line it deletes one character, joining the next line at the end.
let g:AutoPairsMapCh = 0
function! s:DeleteWordForward() abort
    let l:end = searchpos('\k\>', 'cnW', line('.'))[1]
    if l:end == 0
        return "\<Del>"
    endif
    return "\<C-g>u" . repeat("\<Del>", strchars(getline('.')[col('.') - 1 : l:end - 1]))
endfunction
inoremap <C-BS> <C-g>u<C-w>
inoremap <C-h> <C-g>u<C-w>
inoremap <expr> <C-Del> <SID>DeleteWordForward()
cnoremap <C-BS> <C-w>
cnoremap <C-h> <C-w>

" Window navigation with Ctrl+ESDF
nnoremap <C-e> <C-w>k
nnoremap <C-s> <C-w>h
nnoremap <C-d> <C-w>j
nnoremap <C-f> <C-w>l

" Shift+PgUp/PgDn scroll a few lines, as in tmux and its review: tmux's
" @scroll-lines, default 3. Shift+arrows keep Neovim's own meaning.
" Read on the first press, so starting Neovim doesn't wait on tmux.
function! s:ScrollLines() abort
    if !exists('s:scroll_lines')
        let s:scroll_lines = 0
        if executable('tmux')
            let s:scroll_lines = str2nr(trim(system(['tmux', 'show', '-gqv', '@scroll-lines'])))
        endif
        let s:scroll_lines = s:scroll_lines > 0 ? s:scroll_lines : 3
    endif
    return s:scroll_lines
endfunction
nnoremap <expr> <S-PageUp> <SID>ScrollLines() . "\<C-y>"
xnoremap <expr> <S-PageUp> <SID>ScrollLines() . "\<C-y>"
nnoremap <expr> <S-PageDown> <SID>ScrollLines() . "\<C-e>"
xnoremap <expr> <S-PageDown> <SID>ScrollLines() . "\<C-e>"

" Search clearing
nnoremap <silent> <Space> :nohlsearch<CR>

" ==============================================================================
" Plugin Configuration
" ==============================================================================

" Whether plugin NAME is declared above and installed. A plugin's mappings
" are set only when it is, so Neovim without plugins keeps its own keys.
function! s:has_plugin(name) abort
    let l:plug = get(get(g:, 'plugs', {}), a:name, {})
    return has_key(l:plug, 'dir') && isdirectory(l:plug.dir)
endfunction

" FZF - Essential file navigation
if s:has_plugin('fzf.vim')
    nnoremap <C-p> :Files<CR>
    nnoremap <leader>f :Files<CR>
    nnoremap <leader>b :Buffers<CR>
    nnoremap <leader>g :Rg<CR>
endif

" FZF layout
let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.9 } }
let g:fzf_preview_window = ['right:50%', 'ctrl-/']

" Airline
if get(g:, 'colors_name', '') ==# 'dotfiles'
    let g:airline_theme = 'dotfiles'
endif
" Portable default: do not assume a patched Powerline/Nerd Font. Users who
" install one can set this back to 1 in ~/.config/nvim/init.local.vim.
let g:airline_powerline_fonts = 0
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'
let g:airline#extensions#branch#enabled = 1

" Git - Fugitive (main git operations)
if s:has_plugin('vim-fugitive')
    nnoremap <leader>gs :Git<CR>
    nnoremap <leader>gd :Gdiffsplit<CR>
    nnoremap <leader>gc :Git commit<CR>
    nnoremap <leader>gb :Git blame<CR>
endif

" GitGutter (hunk navigation with 'h' prefix)
let g:gitgutter_sign_added = '+'
let g:gitgutter_sign_modified = '~'
let g:gitgutter_sign_removed = '-'
if s:has_plugin('vim-gitgutter')
    nnoremap <leader>hn :GitGutterNextHunk<CR>
    nnoremap <leader>hp :GitGutterPrevHunk<CR>
    nnoremap <leader>hs :GitGutterStageHunk<CR>
    nnoremap <leader>hu :GitGutterUndoHunk<CR>
endif

" Commentary
if s:has_plugin('vim-commentary')
    nnoremap <leader>/ :Commentary<CR>
    vnoremap <leader>/ :Commentary<CR>
endif

" ==============================================================================
" Auto Commands
" ==============================================================================

" Remove trailing whitespace only for formats where it is not semantic. Keep
" the view and search register stable so saving does not move the user.
function! StripTrailingWhitespace()
    if index(['markdown', 'markdown.pandoc', 'text', 'gitcommit', 'diff'], &filetype) >= 0
        return
    endif
    let l:view = winsaveview()
    let l:search = @/
    silent! keeppatterns %s/\s\+$//e
    let @/ = l:search
    call winrestview(l:view)
endfunction

augroup trim_whitespace
    autocmd!
    autocmd BufWritePre * call StripTrailingWhitespace()
augroup END

augroup no_auto_comment
    autocmd!
    autocmd FileType * setlocal formatoptions-=cro
augroup END

" ==============================================================================
" File Type Specific Settings
" ==============================================================================

" Python
augroup python_files
    autocmd!
    autocmd FileType python setlocal expandtab shiftwidth=4 softtabstop=4
    autocmd FileType python setlocal colorcolumn=88
augroup END

" JavaScript/TypeScript
augroup javascript_files
    autocmd!
    autocmd FileType javascript,typescript,javascriptreact,typescriptreact setlocal expandtab shiftwidth=2 softtabstop=2
augroup END

" YAML
augroup yaml_files
    autocmd!
    autocmd FileType yaml setlocal expandtab shiftwidth=2 softtabstop=2
augroup END

" JSON
augroup json_files
    autocmd!
    autocmd FileType json setlocal expandtab shiftwidth=2 softtabstop=2
augroup END

" Markdown
augroup markdown_files
    autocmd!
    autocmd FileType markdown setlocal wrap linebreak nolist
    autocmd FileType markdown setlocal conceallevel=0
augroup END

" Shell scripts
augroup shell_files
    autocmd!
    autocmd FileType sh setlocal expandtab shiftwidth=4 softtabstop=4
augroup END

" ==============================================================================
" Sound and Visual Bell Settings
" ==============================================================================

set noerrorbells
set visualbell
set t_vb=

" ==============================================================================
" Performance Settings
" ==============================================================================

set synmaxcol=500

" Don't highlight huge files
autocmd BufWinEnter * if line('$') > 20000 | syntax clear | endif

set ttyfast

set timeoutlen=500
set ttimeoutlen=10

" ==============================================================================
" Convenience Functions
" ==============================================================================

function! ToggleNumber()
    if(&number == 1)
        set nonumber
    else
        set number
    endif
endfunction
nnoremap <leader>n :call ToggleNumber()<CR>

nnoremap <leader>ss :call StripTrailingWhitespace()<CR>

" ==============================================================================
" Single-purpose profiles
" ==============================================================================

" The tmux review popup (bin/tmux-review) sets NVIM_REVIEW; the compose pane
" (bin/tmux-compose) sets NVIM_PROSE.
if !empty($NVIM_REVIEW) && !empty(nvim_get_runtime_file('lua/dotfiles/review.lua', v:false))
    lua require('dotfiles.review')
endif
if !empty($NVIM_PROSE) && !empty(nvim_get_runtime_file('lua/dotfiles/prose.lua', v:false))
    lua require('dotfiles.prose')
endif

" ==============================================================================
" Local Configuration
" ==============================================================================

if filereadable(stdpath('config') . '/init.local.vim')
    execute 'source ' . fnameescape(stdpath('config') . '/init.local.vim')
endif
