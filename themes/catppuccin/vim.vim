" Catppuccin Mocha theme configuration for Vim
" https://github.com/catppuccin/vim

" Dark background — set before the colorscheme so plugins that branch on
" &background do not pick a light variant after switching from a light theme.
set background=dark

" Catppuccin specific settings
let g:catppuccin_flavour = "mocha"

" Set colorscheme after selecting the flavour.
colorscheme catppuccin_mocha

" Integration settings
let g:airline_theme = 'catppuccin_mocha'
let g:lightline = { 'colorscheme': 'catppuccin_mocha' }
