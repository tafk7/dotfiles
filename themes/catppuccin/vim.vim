" Catppuccin Mocha theme configuration for Vim
" https://github.com/catppuccin/vim

" Dark background — set before the colorscheme so plugins that branch on
" &background do not pick a light variant after switching from a light theme.
set background=dark

" Set colorscheme
colorscheme catppuccin_mocha

" Catppuccin specific settings
let g:catppuccin_flavour = "mocha"

" Integration settings
let g:airline_theme = 'catppuccin_mocha'
let g:lightline = { 'colorscheme': 'catppuccin_mocha' }