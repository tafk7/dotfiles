" Airline theme for the dotfiles colorscheme: palette indices, plus their RGB
" values when the editor is pinned to a theme (see configs/nvim/colors/
" dotfiles.vim). Reverse puts the canvas color on the accent, which reads well
" on light and dark themes alike. Airline calls refresh() on colorscheme changes.
function! s:color(palette, index) abort
  return [get(a:palette, a:index, ''), a:index]
endfunction

function! s:entry(palette, fg, bg, attr) abort
  let [l:guifg, l:ctermfg] = s:color(a:palette, a:fg)
  let [l:guibg, l:ctermbg] = s:color(a:palette, a:bg)
  return [l:guifg, l:guibg, l:ctermfg, l:ctermbg, a:attr]
endfunction

function! airline#themes#dotfiles#refresh() abort
  let l:p = dotfiles#theme#palette(get(g:, 'dotfiles_nvim_theme', ''))
  let l:N2 = s:entry(l:p, 'NONE', '235', '')
  let l:N3 = s:entry(l:p, '245', 'NONE', '')
  let l:inactive = s:entry(l:p, '245', 'NONE', '')
  let g:airline#themes#dotfiles#palette = {}
  let g:airline#themes#dotfiles#palette.normal = airline#themes#generate_color_map(s:entry(l:p, '4', 'NONE', 'reverse,bold'), l:N2, l:N3)
  let g:airline#themes#dotfiles#palette.insert = airline#themes#generate_color_map(s:entry(l:p, '5', 'NONE', 'reverse,bold'), l:N2, l:N3)
  let g:airline#themes#dotfiles#palette.visual = g:airline#themes#dotfiles#palette.insert
  let g:airline#themes#dotfiles#palette.replace = airline#themes#generate_color_map(s:entry(l:p, '1', 'NONE', 'reverse,bold'), l:N2, l:N3)
  let g:airline#themes#dotfiles#palette.inactive = airline#themes#generate_color_map(l:inactive, l:inactive, l:inactive)
endfunction

call airline#themes#dotfiles#refresh()
