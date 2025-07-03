" Tokyo Night theme configuration for Vim
" https://github.com/folke/tokyonight.nvim

" Set colorscheme
colorscheme tokyonight

" Tokyo Night specific settings
let g:tokyonight_style = 'night'
let g:tokyonight_italic_functions = 1
let g:tokyonight_italic_comments = 1
let g:tokyonight_italic_keywords = 1
let g:tokyonight_italic_strings = 0
let g:tokyonight_italic_variables = 0
let g:tokyonight_transparent = 0
let g:tokyonight_hide_inactive_statusline = 0
let g:tokyonight_sidebars = ["qf", "vista_kind", "terminal", "packer"]
let g:tokyonight_transparent_sidebar = 0
let g:tokyonight_dark_sidebar = 1
let g:tokyonight_dark_float = 1
let g:tokyonight_colors = {}
let g:tokyonight_lualine_bold = 1

" Airline theme
let g:airline_theme='tokyonight'