" GitHub Light via projekt0n/github-nvim-theme (MIT).
set background=light
lua << EOF
require('github-theme').setup({
  options = {
    transparent = false,
    styles = { comments = 'italic' },
  },
})
EOF
colorscheme github_light_high_contrast
let g:airline_theme = 'dotfiles'
