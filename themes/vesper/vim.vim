" Vesper theme configuration for Vim
" https://github.com/datsfilipe/vesper.nvim

set background=dark

" Vesper specific settings — must be set BEFORE the colorscheme loads.
" transparent=0 keeps the #101010 canvas; the point of this theme is the
" near-black background, so we do not want the terminal showing through.
let g:vesper_transparent = 0
let g:vesper_italics = 1

" Set colorscheme
colorscheme vesper

" Airline theme — Vesper ships no airline theme; 'minimalist' matches its
" low-chroma, mostly-monochrome intent.
let g:airline_theme = 'minimalist'
