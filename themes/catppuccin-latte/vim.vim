" Catppuccin Latte theme configuration for Vim (light)
" https://github.com/catppuccin/vim

" Light backgrounds need 'background=light' before the colorscheme loads,
" otherwise plugins that branch on &background pick dark variants.
set background=light

" Catppuccin specific settings
let g:catppuccin_flavour = "latte"

" Set colorscheme after selecting the flavour.
colorscheme catppuccin_latte

" Integration settings
let g:airline_theme = 'catppuccin_latte'
let g:lightline = { 'colorscheme': 'catppuccin_latte' }
