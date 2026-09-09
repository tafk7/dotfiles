" Kanagawa theme configuration for Vim
" https://github.com/rebelot/kanagawa.nvim

" Dark background — set before the colorscheme so plugins that branch on
" &background do not pick a light variant after switching from a light theme.
set background=dark

lua << EOF
require('kanagawa').setup({
  transparent = false,
  terminalColors = true,
  commentStyle = { italic = true },
  keywordStyle = { italic = true },
  statementStyle = { bold = true },
  theme = 'wave',
})
EOF
colorscheme kanagawa-wave

" Airline theme (use a compatible dark theme)
let g:airline_theme='dotfiles'
