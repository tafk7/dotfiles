" Everforest theme configuration for Vim
" https://github.com/sainnhe/everforest

set background=dark

" Everforest specific settings — must be set BEFORE the colorscheme loads.
let g:everforest_background = 'medium'
let g:everforest_better_performance = 1
let g:everforest_enable_italic = 1
let g:everforest_transparent_background = 0
let g:everforest_diagnostic_text_highlight = 1
let g:everforest_diagnostic_line_highlight = 0
let g:everforest_current_word = 'grey background'

" Set colorscheme
colorscheme everforest

" Airline theme
let g:airline_theme = 'everforest'
