" Modern Vim Configuration with Power User Features
" Part of dotfiles

" ==============================================================================
" Vim-Plug Auto-Installation
" ==============================================================================

" Plugin installation is an explicit setup action. Ordinary editor startup
" never downloads or executes remote code.

" ==============================================================================
" Plugins
" ==============================================================================

let s:vim_plug = expand('~/.config/nvim/autoload/plug.vim')
if filereadable(s:vim_plug)
execute 'source ' . fnameescape(s:vim_plug)
call plug#begin('~/.config/nvim/plugged')

" Color schemes
Plug 'morhetz/gruvbox', { 'commit': '5d15b2765f59754d7ac263c88a0f6e3e58124951' }
Plug 'sainnhe/gruvbox-material', { 'commit': '11d779b26a9ab2b3db8c22c6ac9fb6e8ed4fea79' }
Plug 'folke/tokyonight.nvim', { 'commit': 'cdc07ac78467a233fd62c493de29a17e0cf2b2b6' }
Plug 'rebelot/kanagawa.nvim', { 'commit': 'bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3' }
Plug 'catppuccin/vim', { 'as': 'catppuccin', 'commit': 'ee7d87e1c3f753069dae41df139f7d3fd914f7e9' }
Plug 'sainnhe/everforest', { 'commit': '85a86eb62409e3ec88713bff3d1b9d7374e112e4' }
Plug 'datsfilipe/vesper.nvim', { 'commit': '1717b1ad657c94bec3fc2bdebb0c55452d9fe46d' }
Plug 'projekt0n/github-nvim-theme', { 'commit': 'c106c9472154d6b2c74b74565616b877ae8ed31d' }

" Essential tpope plugins
Plug 'tpope/vim-fugitive', { 'commit': '3b753cf8c6a4dcde6edee8827d464ba9b8c4a6f0' }
Plug 'tpope/vim-surround', { 'commit': '3d188ed2113431cf8dac77be61b842acb64433d9' }
Plug 'tpope/vim-commentary', { 'commit': '64a654ef4a20db1727938338310209b6a63f60c9' }
Plug 'tpope/vim-repeat', { 'commit': '65846025c15494983dafe5e3b46c8f88ab2e9635' }
Plug 'tpope/vim-unimpaired', { 'commit': 'db65482581a28e4ccf355be297f1864a4e66985c' }

" File navigation
Plug 'junegunn/fzf', { 'commit': 'b224480a98a40c670c8ed89abd52d4216a470032', 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim', { 'commit': '8a0068127ac9ee23d71dab2944ce995726bef462' }

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
Plug 'dense-analysis/ale', { 'commit': 'e1789bc54483d76ac9ddb40b633d1645c8281914' }

call plug#end()
endif
unlet s:vim_plug

" ==============================================================================
" Basic Settings
" ==============================================================================

" Use Vim settings, not Vi
set nocompatible

" Enable modern Vim features
set encoding=utf-8
setglobal fileencoding=utf-8

" Enable file type detection and plugins
filetype plugin indent on

" Enable syntax highlighting
syntax enable

" ==============================================================================
" Visual Settings
" ==============================================================================

" Color scheme configuration
set background=dark
if (has("termguicolors"))
    set termguicolors
endif

" Configure terminal colors for better compatibility
if &term =~ '256color'
    " Disable Background Color Erase (BCE)
    set t_ut=
endif

" Dynamic scoped theme loading
if exists('$DOTFILES_DIR') && filereadable($DOTFILES_DIR . '/lib/theme.vim')
    execute 'set runtimepath^=' . fnameescape($DOTFILES_DIR . '/configs/nvim')
    execute 'source ' . fnameescape($DOTFILES_DIR . '/lib/theme.vim')
else
    " Default theme fallback
    try
        let g:gruvbox_material_background = 'medium'
        let g:gruvbox_material_better_performance = 1
        colorscheme gruvbox-material
    catch
        colorscheme desert
    endtry
endif

" Show line numbers
set number
" Relative numbers disabled - using absolute line numbers only
" set relativenumber

" Highlight current line
set cursorline

" Show matching brackets
set showmatch

" Always show status line
set laststatus=2

" Show command in bottom bar
set showcmd

" Visual autocomplete for command menu
set wildmenu
set wildmode=longest:full,full
set wildignorecase

" Redraw only when needed (faster macros)
set lazyredraw

" ==============================================================================
" Search Settings
" ==============================================================================

" Highlight search results
set hlsearch

" Incremental search
set incsearch

" Case-insensitive search
set ignorecase

" Smart case (case-sensitive if uppercase used)
set smartcase

" Clear search highlighting with Space
nnoremap <silent> <Space> :nohlsearch<CR>

" ==============================================================================
" Indentation and Formatting
" ==============================================================================

" Spaces instead of tabs
set expandtab

" Number of spaces per tab
set tabstop=4
set softtabstop=4
set shiftwidth=4

" Auto indent
set autoindent
set smartindent

" Wrap lines at convenient points
set linebreak

" Don't wrap lines by default
set nowrap

" Show invisible characters
set list
set listchars=tab:▸\ ,trail:·,extends:❯,precedes:❮,nbsp:×

" ==============================================================================
" Mouse and Clipboard
" ==============================================================================

" Enable mouse support
if has('mouse')
    set mouse=a
    if !has('nvim')
        set ttymouse=xterm2
    endif
endif

" Use system clipboard
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

" Disable swap files
set noswapfile

" Disable backup files
set nobackup
set nowritebackup

" Keep undo history across sessions
if has('persistent_undo')
    set undofile
    set undodir=~/.config/nvim/undo
    if !isdirectory(&undodir)
        call mkdir(&undodir, 'p')
    endif
endif

" Auto read when file is changed externally
set autoread

" Better path handling
set path+=**

" ==============================================================================
" Window Management
" ==============================================================================

" Split windows to the right and below
set splitright
set splitbelow

" Minimum window height
set winminheight=0

" ==============================================================================
" Key Mappings
" ==============================================================================

" Set leader key
let mapleader = ","
let g:mapleader = ","

" File operations
nnoremap <leader>w :w!<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>Q :qa!<CR>

" Better escape (keep both Esc and jk)
inoremap jk <Esc>

" Window navigation with Ctrl+ESDF
nnoremap <C-e> <C-w>k
nnoremap <C-s> <C-w>h
nnoremap <C-d> <C-w>j
nnoremap <C-f> <C-w>l

" Half-page scrolling with Shift+arrows
nnoremap <S-Up> <C-u>
nnoremap <S-Down> <C-d>

" Search clearing
nnoremap <silent> <Space> :nohlsearch<CR>

" ==============================================================================
" Plugin Configuration
" ==============================================================================

" FZF - Essential file navigation
nnoremap <C-p> :Files<CR>
nnoremap <leader>f :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>g :Rg<CR>

" FZF layout
let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.9 } }
let g:fzf_preview_window = ['right:50%', 'ctrl-/']

" Airline
" Theme will be set by theme loader, but provide a default
if !exists('g:airline_theme')
    let g:airline_theme='gruvbox_material'
endif
" Portable default: do not assume a patched Powerline/Nerd Font. Users who
" install one can set this back to 1 in ~/.config/nvim/init.local.vim.
let g:airline_powerline_fonts = 0
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#formatter = 'unique_tail'
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#ale#enabled = 1

" Git - Fugitive (main git operations)
nnoremap <leader>gs :Git<CR>
nnoremap <leader>gd :Gdiffsplit<CR>
nnoremap <leader>gc :Git commit<CR>
nnoremap <leader>gb :Git blame<CR>

" GitGutter (hunk navigation with 'h' prefix)
let g:gitgutter_sign_added = '+'
let g:gitgutter_sign_modified = '~'
let g:gitgutter_sign_removed = '-'
nnoremap <leader>hn :GitGutterNextHunk<CR>
nnoremap <leader>hp :GitGutterPrevHunk<CR>
nnoremap <leader>hs :GitGutterStageHunk<CR>
nnoremap <leader>hu :GitGutterUndoHunk<CR>

" ALE (Async Lint Engine)
let g:ale_sign_error = '●'
let g:ale_sign_warning = '.'
let g:ale_lint_on_enter = 0
let g:ale_lint_on_text_changed = 'delay'
let g:ale_echo_msg_format = '[%linter%] %s [%severity%]'
let g:ale_linters = {
\   'python': ['ruff'],
\   'javascript': ['eslint'],
\   'typescript': ['tsserver', 'eslint'],
\}
let g:ale_fixers = {
\   '*': ['remove_trailing_lines', 'trim_whitespace'],
\   'python': ['black', 'ruff'],
\   'javascript': ['prettier'],
\   'typescript': ['prettier'],
\}
nnoremap <leader>af :ALEFix<CR>
nnoremap <leader>an :ALENext<CR>
nnoremap <leader>ap :ALEPrevious<CR>

" Commentary
nnoremap <leader>/ :Commentary<CR>
vnoremap <leader>/ :Commentary<CR>

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

" Disable automatic comment insertion
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

" Disable error bells
set noerrorbells
set visualbell
set t_vb=

" ==============================================================================
" Performance Settings
" ==============================================================================

" Limit syntax highlighting for long lines
set synmaxcol=500

" Don't highlight huge files
autocmd BufWinEnter * if line('$') > 20000 | syntax clear | endif

" Faster scrolling
set ttyfast

" Reduce timeout delays
set timeoutlen=500
set ttimeoutlen=10

" ==============================================================================
" Convenience Functions
" ==============================================================================

" Toggle line numbers on/off
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
" Local Configuration
" ==============================================================================

" Source local configuration if it exists
if filereadable(expand("~/.config/nvim/init.local.vim"))
    source ~/.config/nvim/init.local.vim
endif
