" Modern Vim Configuration
" Part of dotfiles - https://github.com/yourusername/dotfiles

" ==============================================================================
" Basic Settings
" ==============================================================================

" Use Vim settings, not Vi
set nocompatible

" Enable modern Vim features not compatible with Vi
set encoding=utf-8
set fileencoding=utf-8

" Enable file type detection and plugins
filetype on
filetype plugin on
filetype indent on

" Enable syntax highlighting
syntax enable
syntax on

" ==============================================================================
" Visual Settings
" ==============================================================================

" Color scheme configuration
set background=dark
if (has("termguicolors"))
    set termguicolors
endif

" Configure terminal colors for better compatibility
set term=xterm-256color
if &term =~ '256color'
    " Disable Background Color Erase (BCE) for proper rendering
    " in 256-color tmux and GNU screen
    set t_ut=
endif

" Try to load gruvbox colorscheme, fallback to desert
try
    colorscheme gruvbox
catch
    colorscheme desert
endtry

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
nnoremap <Space> :nohlsearch<CR>

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
    set undodir=~/.vim/undo
    if !isdirectory(&undodir)
        call mkdir(&undodir, 'p')
    endif
endif

" Auto read when file is changed externally
set autoread

" Automatically change working directory to current file
set autochdir

" ==============================================================================
" Window Management
" ==============================================================================

" Split windows to the right and below
set splitright
set splitbelow

" Minimum window height
set winminheight=0

" Easy window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" ==============================================================================
" Key Mappings
" ==============================================================================

" Set leader key
let mapleader = ","

" Fast saving
nnoremap <leader>w :w!<CR>

" Fast quitting
nnoremap <leader>q :q<CR>

" Move between tabs
nnoremap <F9> :tabprevious<CR>
nnoremap <F10> :tabnext<CR>
nnoremap <F2> :tabm -1<CR>
nnoremap <F3> :tabm +1<CR>

" Open file under cursor in new vertical split
nnoremap <F8> :vertical wincmd f<CR>

" Move lines up and down
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" Better scrolling
nnoremap <C-e> 3<C-e>
nnoremap <C-y> 3<C-y>

" Delete without yanking (using black hole register)
nnoremap <leader>d "_d
nnoremap <leader>D "_D
nnoremap <leader>c "_c
nnoremap <leader>C "_C
vnoremap <leader>d "_d
vnoremap <leader>D "_D
vnoremap <leader>c "_c
vnoremap <leader>C "_C
nnoremap <Del> "_x
vnoremap <Del> "_x

" Replace without yanking
vnoremap <leader>p "_dP

" Paste in visual mode without yanking
function! RestoreRegister()
    let @" = s:restore_reg
    return ''
endfunction
function! s:Repl()
    let s:restore_reg = @"
    return "p@=RestoreRegister()\<cr>"
endfunction
vnoremap <silent> <expr> p <sid>Repl()
vnoremap <silent> <expr> P <sid>Repl()

" ==============================================================================
" Sound and Visual Bell Settings
" ==============================================================================

" Disable error bells
set noerrorbells
set visualbell
set t_vb=
autocmd GUIEnter * set visualbell t_vb=

" ==============================================================================
" Cursor Settings
" ==============================================================================

" Set cursor styles for different modes
let &t_SI.="\e[5 q" " SI = INSERT mode (blinking bar)
let &t_EI.="\e[1 q" " EI = NORMAL mode (blinking block)

" ==============================================================================
" Plugin Configuration (if plugins are installed)
" ==============================================================================

" FZF configuration (if installed)
if isdirectory($HOME . '/.fzf')
    set rtp+=~/.fzf
    nnoremap <C-p> :FZF<CR>
    nnoremap <leader>b :Buffers<CR>
    nnoremap <leader>f :Files<CR>
    nnoremap <leader>g :Rg<CR>
endif

" Use ripgrep for grep if available
if executable('rg')
    set grepprg=rg\ --vimgrep\ --smart-case\ --follow
endif

" Use ag (silver searcher) if available but rg is not
if !executable('rg') && executable('ag')
    set grepprg=ag\ --vimgrep
    let g:ackprg = 'ag --vimgrep --nogroup --nocolor --column'
endif

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
augroup END

" Shell scripts
augroup shell_files
    autocmd!
    autocmd FileType sh setlocal expandtab shiftwidth=4 softtabstop=4
augroup END

" ==============================================================================
" GUI Settings (if using gVim)
" ==============================================================================

if has('gui_running')
    " Remove toolbar
    set guioptions-=T
    " Remove scrollbars
    set guioptions-=r
    set guioptions-=L
    " Use console dialogs
    set guioptions+=c
    " Set font
    if has('gui_gtk')
        set guifont=Cascadia\ Code\ PL\ 12
    elseif has('gui_macvim')
        set guifont=Cascadia\ Code\ PL:h12
    elseif has('gui_win32')
        set guifont=Cascadia_Code_PL:h12:cANSI
    endif
endif

" ==============================================================================
" Performance Settings
" ==============================================================================

" Limit syntax highlighting for long lines
set synmaxcol=500

" Don't highlight huge files
autocmd BufWinEnter * if line('$') > 20000 | syntax clear | endif

" Faster scrolling
set ttyfast

" ==============================================================================
" Security Settings
" ==============================================================================

" Disable modelines for security
set nomodeline
set modelines=0

" Secure external command execution
set secure

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
" Status Line
" ==============================================================================

" Simple but informative status line
set statusline=
set statusline+=%f                          " File path
set statusline+=\ %m                        " Modified flag
set statusline+=\ %r                        " Readonly flag
set statusline+=\ %h                        " Help file flag
set statusline+=%=                          " Left/right separator
set statusline+=%y                          " File type
set statusline+=\ [%{&fileencoding?&fileencoding:&encoding}]  " Encoding
set statusline+=\ [%{&fileformat}]          " File format
set statusline+=\ %p%%                      " Percentage through file
set statusline+=\ %l:%c                     " Line:Column
set statusline+=\ 

" ==============================================================================
" Local Configuration
" ==============================================================================

" Source local configuration if it exists
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif