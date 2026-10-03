" Airline theme for the dotfiles colorscheme: palette indices only (see
" configs/nvim/colors/dotfiles.vim). Reverse puts the window's background color
" on the accent, which reads well on light and dark themes alike.
let s:N1 = ['', '', '4', 'NONE', 'reverse,bold']
let s:N2 = ['', '', 'NONE', '235', '']
let s:N3 = ['', '', '245', 'NONE', '']
let s:I1 = ['', '', '5', 'NONE', 'reverse,bold']
let s:R1 = ['', '', '1', 'NONE', 'reverse,bold']
let s:inactive = ['', '', '245', 'NONE', '']

let g:airline#themes#dotfiles#palette = {}
let g:airline#themes#dotfiles#palette.normal = airline#themes#generate_color_map(s:N1, s:N2, s:N3)
let g:airline#themes#dotfiles#palette.insert = airline#themes#generate_color_map(s:I1, s:N2, s:N3)
let g:airline#themes#dotfiles#palette.visual = airline#themes#generate_color_map(s:I1, s:N2, s:N3)
let g:airline#themes#dotfiles#palette.replace = airline#themes#generate_color_map(s:R1, s:N2, s:N3)
let g:airline#themes#dotfiles#palette.inactive = airline#themes#generate_color_map(s:inactive, s:inactive, s:inactive)
