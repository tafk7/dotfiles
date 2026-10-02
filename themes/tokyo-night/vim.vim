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

colorscheme tokyonight-night
