" Kanagawa Dragon theme configuration for Vim
" https://github.com/rebelot/kanagawa.nvim — 'dragon' variant

set background=dark

lua << EOF
require('kanagawa').setup({
  transparent = false,
  terminalColors = true,
  commentStyle = { italic = true },
  keywordStyle = { italic = true },
  statementStyle = { bold = true },
  theme = 'dragon',
})
EOF
colorscheme kanagawa-dragon

" Airline theme (use a compatible dark theme)
let g:airline_theme='dotfiles'
