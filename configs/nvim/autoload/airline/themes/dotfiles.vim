" Exact adapter for the currently resolved dotfiles palette.
let s:bg = get(g:, 'dotfiles_airline_bg', '#282828')
let s:fg = get(g:, 'dotfiles_airline_fg', '#d4be98')
let s:secondary = get(g:, 'dotfiles_airline_secondary', '#a89984')
let s:surface = get(g:, 'dotfiles_airline_surface', '#3c3836')
let s:accent = get(g:, 'dotfiles_airline_accent', '#7daea3')
let s:accent2 = get(g:, 'dotfiles_airline_accent2', '#d8a657')
let s:red = get(g:, 'dotfiles_airline_red', '#ea6962')

let s:N1 = [s:bg, s:accent, '', '', 'bold']
let s:N2 = [s:fg, s:surface, '', '']
let s:N3 = [s:secondary, s:bg, '', '']
let g:airline#themes#dotfiles#palette = {}
let g:airline#themes#dotfiles#palette.normal = airline#themes#generate_color_map(s:N1, s:N2, s:N3)
let g:airline#themes#dotfiles#palette.insert = airline#themes#generate_color_map([s:bg, s:accent2, '', '', 'bold'], s:N2, s:N3)
let g:airline#themes#dotfiles#palette.replace = airline#themes#generate_color_map([s:bg, s:red, '', '', 'bold'], s:N2, s:N3)
let g:airline#themes#dotfiles#palette.visual = airline#themes#generate_color_map([s:bg, s:accent2, '', '', 'bold'], s:N2, s:N3)
let g:airline#themes#dotfiles#palette.inactive = airline#themes#generate_color_map([s:secondary, s:surface, '', ''], [s:secondary, s:bg, '', ''], [s:secondary, s:bg, '', ''])
