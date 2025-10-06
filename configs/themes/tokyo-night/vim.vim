" Tokyo Night theme configuration for Vim
" https://github.com/folke/tokyonight.nvim

" Tokyo Night specific settings (set before loading colorscheme)
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

" Set colorscheme with error handling
try
    colorscheme tokyonight
    " Use a compatible airline theme (tokyonight doesn't have native airline support)
    let g:airline_theme='deus'
catch
    " Fallback if tokyonight not available
    colorscheme desert
    let g:airline_theme='dark'
endtry