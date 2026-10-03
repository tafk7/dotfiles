" Neovim theme pinning. By default the dotfiles colorscheme uses palette
" indices and follows the tmux window's theme. A pin (`:Theme NAME`, or
" `theme --nvim NAME` for every new editor) switches it to RGB colors read from
" themes/NAME.sh, so this editor keeps that theme whatever the window uses.

function! s:themes_dir() abort
  return exists('$DOTFILES_DIR') ? $DOTFILES_DIR . '/themes' : ''
endfunction

function! dotfiles#theme#names() abort
  let l:dir = s:themes_dir()
  return empty(l:dir) ? [] : map(glob(l:dir . '/*.sh', 0, 1), 'fnamemodify(v:val, ":t:r")')
endfunction

function! dotfiles#theme#complete(arglead, ...) abort
  return filter(['follow'] + dotfiles#theme#names(), 'stridx(v:val, a:arglead) == 0')
endfunction

" The pin saved by `theme --nvim`, or '' to follow the window.
function! dotfiles#theme#saved() abort
  let l:dir = exists('$DOTFILES_STATE_DIR') ? $DOTFILES_STATE_DIR
        \ : (exists('$XDG_STATE_HOME') ? $XDG_STATE_HOME : $HOME . '/.local/state') . '/dotfiles'
  let l:file = l:dir . '/theme.tsv'
  if !filereadable(l:file)
    return ''
  endif
  for l:line in readfile(l:file)
    let l:fields = split(l:line, "\t", 1)
    if len(l:fields) == 2 && l:fields[0] ==# 'nvim'
      return index(dotfiles#theme#names(), l:fields[1]) >= 0 ? l:fields[1] : ''
    endif
  endfor
  return ''
endfunction

" Same integer mix as bin/theme-switcher's blend(): pct percent of a.
function! s:blend(a, b, pct) abort
  let l:out = '#'
  for l:i in [1, 3, 5]
    let l:x = str2nr(a:a[l:i : l:i + 1], 16)
    let l:y = str2nr(a:b[l:i : l:i + 1], 16)
    let l:out .= printf('%02x', (l:x * a:pct + l:y * (100 - a:pct)) / 100)
  endfor
  return l:out
endfunction

" RGB for each palette index the colorscheme uses, plus 'fg' and 'bg'; the
" same mapping tmux applies with pane-colours[]. Empty for an unknown theme.
function! dotfiles#theme#palette(name) abort
  let l:file = s:themes_dir() . '/' . a:name . '.sh'
  if a:name !~# '^[a-z0-9-]\+$' || !filereadable(l:file)
    return {}
  endif
  let l:role = {}
  let l:ansi = []
  for l:line in readfile(l:file)
    let l:match = matchlist(l:line, "^THEME_\\([A-Z0-9_]\\+\\)_HEX='\\(#\\x\\{6}\\)'")
    if !empty(l:match)
      let l:role[l:match[1]] = l:match[2]
    elseif l:line =~# '^THEME_ANSI='
      let l:ansi = map(split(matchstr(l:line, '(\zs.*\ze)')), "trim(v:val, \"'\")")
    endif
  endfor
  if len(l:ansi) != 16
    return {}
  endif
  let l:p = {'fg': l:role.FG, 'bg': l:role.BG,
        \ '235': l:role.SURFACE, '238': l:role.SURFACE_2, '240': l:role.BORDER, '245': l:role.SECONDARY,
        \ '22': s:blend(l:role.GREEN, l:role.BG, 14), '52': s:blend(l:role.RED, l:role.BG, 14),
        \ '28': s:blend(l:role.GREEN, l:role.BG, 24), '88': s:blend(l:role.RED, l:role.BG, 24)}
  for l:i in range(16)
    let l:p[string(l:i)] = l:ansi[l:i]
  endfor
  return l:p
endfunction

" :Theme NAME pins this editor; :Theme follow follows the window again.
function! dotfiles#theme#set(name) abort
  if empty(a:name)
    echo empty(get(g:, 'dotfiles_nvim_theme', '')) ? 'Following the tmux window theme'
          \ : 'Pinned to ' . g:dotfiles_nvim_theme
    return
  endif
  if a:name !=# 'follow' && empty(dotfiles#theme#palette(a:name))
    echohl ErrorMsg | echo 'Theme not found: ' . a:name | echohl None
    return
  endif
  let g:dotfiles_nvim_theme = a:name ==# 'follow' ? '' : a:name
  colorscheme dotfiles
  if exists(':AirlineRefresh') == 2
    AirlineRefresh
  endif
endfunction
