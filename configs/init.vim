" Modern Vim Configuration with Power User Features
" Part of dotfiles - https://github.com/yourusername/dotfiles

" ==============================================================================
" Vim-Plug Auto-Installation
" ==============================================================================

" Install vim-plug if not found
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" ==============================================================================
" Plugins
" ==============================================================================

call plug#begin('~/.config/nvim/plugged')

" Color schemes
Plug 'morhetz/gruvbox'                        " Retro groove color scheme
Plug 'sainnhe/gruvbox-material'              " Softer variant of gruvbox
Plug 'arcticicestudio/nord-vim'              " Nord color scheme
Plug 'folke/tokyonight.nvim'                 " Tokyo Night color scheme
Plug 'rebelot/kanagawa.nvim'                 " Kanagawa color scheme
Plug 'catppuccin/vim', { 'as': 'catppuccin' } " Catppuccin color scheme

" Essential tpope plugins
Plug 'tpope/vim-fugitive'                     " Git integration
Plug 'tpope/vim-surround'                     " Surround text objects
Plug 'tpope/vim-commentary'                   " Quick commenting
Plug 'tpope/vim-repeat'                       " Repeat plugin commands
Plug 'tpope/vim-unimpaired'                   " Bracket mappings

" File navigation
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'                       " FZF integration

" Git integration
Plug 'airblade/vim-gitgutter'                 " Git diff in gutter

" Editing enhancements
Plug 'jiangmiao/auto-pairs'                   " Auto close brackets

" UI enhancements
Plug 'vim-airline/vim-airline'                " Status line
Plug 'vim-airline/vim-airline-themes'         " Airline themes
Plug 'machakann/vim-highlightedyank'          " Highlight yanked text

" Syntax and language support
Plug 'sheerun/vim-polyglot'                   " Language pack
Plug 'dense-analysis/ale'                     " Async linting

call plug#end()

" ==============================================================================
" Basic Settings
" ==============================================================================

" Use Vim settings, not Vi
set nocompatible

" Enable modern Vim features
set encoding=utf-8
set fileencoding=utf-8

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

" Dynamic theme loading
" Source theme configuration if it exists
if filereadable(expand("~/.config/nvim/theme.vim"))
    source ~/.config/nvim/theme.vim
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
set relativenumber

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
let g:airline_powerline_fonts = 1
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

" Return to last edit position when opening files
augroup remember_position
    autocmd!
    autocmd BufReadPost *
        \ if line("'\"") > 0 && line("'\"") <= line("$") |
        \   exe "normal! g`\"" |
        \ endif
augroup END

" Automatically remove trailing whitespace on save
augroup trim_whitespace
    autocmd!
    autocmd BufWritePre * :%s/\s\+$//e
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
set ttimeoutlen=0

" ==============================================================================
" Convenience Functions
" ==============================================================================

" Toggle between number and relativenumber
function! ToggleNumber()
    if(&relativenumber == 1)
        set norelativenumber
        set number
    else
        set relativenumber
    endif
endfunction
nnoremap <leader>n :call ToggleNumber()<CR>

" Strip trailing whitespace
function! StripTrailingWhitespace()
    let save_cursor = getpos(".")
    %s/\s\+$//e
    call setpos('.', save_cursor)
endfunction
nnoremap <leader>ss :call StripTrailingWhitespace()<CR>

" ==============================================================================
" Local Configuration
" ==============================================================================

" Source local configuration if it exists
if filereadable(expand("~/.config/nvim/init.local.vim"))
    source ~/.config/nvim/init.local.vim
endif