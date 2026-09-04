" Catppuccin Latte theme configuration for Vim (light)
" https://github.com/catppuccin/vim

" Light backgrounds need 'background=light' before the colorscheme loads,
" otherwise plugins that branch on &background pick dark variants.
set background=light

" Set colorscheme
colorscheme catppuccin_latte

" Catppuccin specific settings
let g:catppuccin_flavour = "latte"

" Integration settings
let g:airline_theme = 'catppuccin_latte'
let g:lightline = { 'colorscheme': 'catppuccin_latte' }
