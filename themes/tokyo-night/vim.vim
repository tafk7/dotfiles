" Tokyo Night theme configuration for Vim
" https://github.com/folke/tokyonight.nvim

" Dark background — set before the colorscheme so plugins that branch on
" &background do not pick a light variant after switching from a light theme.
set background=dark

lua << EOF
require('tokyonight').setup({
  style = 'night',
  transparent = false,
  terminal_colors = true,
  styles = {
    comments = { italic = true },
    keywords = { italic = true },
    functions = {},
    variables = {},
    sidebars = 'dark',
    floats = 'dark',
  },
})
EOF

" Set colorscheme with error handling
try
    colorscheme tokyonight-night
    let g:airline_theme='dotfiles'
catch
    " Fallback if tokyonight not available
    colorscheme desert
    let g:airline_theme='dark'
endtry
