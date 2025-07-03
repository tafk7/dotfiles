" Kanagawa theme configuration for Vim
" https://github.com/rebelot/kanagawa.nvim

" Set colorscheme
colorscheme kanagawa

" Kanagawa specific settings
let g:kanagawa_transparent = 0
let g:kanagawa_terminal_colors = 1
let g:kanagawa_italic_comments = 1
let g:kanagawa_italic_keywords = 1
let g:kanagawa_italic_functions = 0
let g:kanagawa_italic_strings = 0
let g:kanagawa_italic_variables = 0
let g:kanagawa_contrast = "medium"
let g:kanagawa_contrast_dark = "medium"
let g:kanagawa_disable_background = 0
let g:kanagawa_cursorline_transparent = 0

" Airline theme (use a compatible dark theme)
let g:airline_theme='minimalist'