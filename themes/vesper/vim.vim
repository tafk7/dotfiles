" Vesper theme configuration for Vim
" https://github.com/datsfilipe/vesper.nvim

set background=dark

lua << EOF
require('vesper').setup({
  transparent = false,
  italics = {
    comments = true,
    keywords = true,
    functions = true,
    strings = true,
    variables = true,
  },
})
EOF

" Set colorscheme
colorscheme vesper

let g:airline_theme = 'dotfiles'
