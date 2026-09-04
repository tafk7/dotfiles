" Rosé Pine Dawn theme configuration for Vim (light)
" https://github.com/rose-pine/neovim

" Light backgrounds need 'background=light' before the colorscheme loads,
" otherwise plugins that branch on &background pick dark variants.
set background=light

" Rosé Pine specific settings — the 'dawn' variant is selected by &background
" on rose-pine/neovim; 'rose-pine-dawn' pins it explicitly.
let g:rose_pine_variant = 'dawn'
let g:rose_pine_disable_background = 0
let g:rose_pine_bold_vertical_split_line = 1

" Set colorscheme
colorscheme rose-pine-dawn

" Airline theme
let g:airline_theme = 'rose_pine_dawn'
