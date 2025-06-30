" Configure terminal color scheme
" set term=screen-256color
set term=xterm-256color
if &term =~ '256color'
    " disable Background Color Erase (BCE) so that color schemes
    " render properly when inside 256-color tmux and GNU screen.
    " see also http://snk.tuxfamily.org/log/vim-256color-bce.html
    set t_ut=
endif


set background=dark
set mouse=a

autocmd vimenter * colorscheme gruvbox

" Load color scheme
"colorscheme neuromancer
"colorscheme lizard 
"colorscheme gruvbox
"colorscheme molokai
"colorscheme solarized

" Start Pathogen package manager
execute pathogen#infect()

" Use ag
let g:ackprg = 'ag --nogroup --nocolor --column'

" Enable syntax highlighting, file type detection, file type specific indentation, and plugins.
filetype on
filetype indent on
filetype plugin on
syntax enable
syntax on

" Disable blinking and bells
set noeb vb t_vb=
au GUIEnter * set vb t_vb=

" Set cursor style
let &t_SI.="\e[5 q" "SI = INSERT mode
" let &t_SR.="\e[4 q" "SR = REPLACE mode
let &t_EI.="\e[1 q" "EI = NORMAL mode (ELSE)

" Show command, useful for # of characters/lines in Visual selection
set showcmd

" Set tab to be 4 space characters
set tabstop=4
set shiftwidth=4
set expandtab

" Smart case matching for search
set smartcase
set ignorecase

" Enable mouse
set mouse=an
set ttymouse=xterm2

" Set line numbers
set number
highlight LineNr ctermfg=grey

" Turn off wrapping
set nowrap

" Highlight searches
set hlsearch

" Clear search highlighting
map <Space> :noh<cr>

" Remap C-e and C-y to 3 lines
nnoremap <C-e> 3<C-e>
nnoremap <C-y> 3<C-y>

" Remap F9 to previous tab and F10 to next tab
noremap <F10> :<C-U>tabnext<CR>
noremap <F9> :<C-U>tabprevious<CR>
noremap <C-Tab> :<C-U>tabnext<CR>
noremap <C-S-Tab> :<C-U>tabprevious<CR>
noremap <F2> :<C-U>tabm-1<CR>
noremap <F3> :<C-U>tabm+1<CR>

" Automatically change working directory
set autochdir

" Split vertical window to the right, horizontal windows below
set splitright
set splitbelow

" FZF funtime path for Vim
set rtp+=~/.fzf

" Nerdtree stuff
" call plug#begin()
" Plug 'scrooloose/nerdtree'
" call plug#end()
" map <C-n> :NERDTreeToggle<CR>

" Load color cycle script
"runtime autoload/cyclecolor.vim

" Provide versions of cut and delete in normal and visual modes that don't
" yank the elements. These disable yank by using the black hole register.
nnoremap <leader>d "_d
nnoremap <leader>D "_d
nnoremap <leader>c "_c
nnoremap <leader>C "_C
vnoremap <leader>d "_d
vnoremap <leader>D "_D
vnoremap <leader>c "_c
vnoremap <leader>C "_C

" Override the default behavior of the <Del> key, and prevent it from
" automatically yanking the text it deletes.
noremap <Del> "_x

" Override the default behavior of the paste command in visual mode. Instead
" of yanking the selection that was pasted over, simply delete it.
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

" Ignore case for file autocompletion
set wildignorecase

" Disable Swap Files
set noswapfile

" Disable Autocomment
set formatoptions-=cro

" Set .ps1 filetype to .tcl to make syntax nice
au BufNewFile,BufRead,BufReadPost *.ps1 set syntax=tcl

" Set .hwlib.yml filetype to .tcl to make syntax nice
au BufNewFile,BufRead,BufReadPost *.hwlib.yml set syntax=tcl

" Set .yml filetype to .tcl to make syntax nice
au BufNewFile,BufRead,BufReadPost *.yml set syntax=tcl

set rtp+=~/.fzf

" Remap F8 to do gf, but split in new window
nnoremap <F8> :vertical wincmd f<CR>
