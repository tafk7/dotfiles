" Runtime Neovim theme resolver. New instances use the shell-resolved window
" context; :ThemeReload asks the switcher again for long-running instances.

function! s:ThemePalette(theme) abort
  let l:palette = {}
  if !exists('$DOTFILES_DIR')
    return l:palette
  endif
  let l:cmd = shellescape($DOTFILES_DIR . '/bin/theme-switcher') . ' palette ' . shellescape(a:theme)
  for l:line in systemlist(l:cmd)
    let l:parts = split(l:line, '=', 1)
    if len(l:parts) == 2
      let l:palette[l:parts[0]] = l:parts[1]
    endif
  endfor
  return l:palette
endfunction

" Return the first colorscheme named by a theme adapter. Checking runtimepath
" before sourcing avoids E185 and Lua module errors when optional editor
" plugins have not been installed on a fresh/headless machine.
function! s:ThemeColorScheme(file) abort
  for l:line in readfile(a:file)
    let l:match = matchlist(l:line, '^\s*colorscheme\s\+\([^[:space:]]\+\)')
    if len(l:match) > 1
      return l:match[1]
    endif
  endfor
  return ''
endfunction

function! DotfilesThemeReload(...) abort
  if exists('$DOTFILES_THEME_ENABLED') && $DOTFILES_THEME_ENABLED ==# '0'
    silent! colorscheme default
    return
  endif
  if !exists('$DOTFILES_DIR') || !executable($DOTFILES_DIR . '/bin/theme-switcher')
    silent! colorscheme default
    return
  endif
  call system(shellescape($DOTFILES_DIR . '/bin/theme-switcher') . ' enabled')
  if v:shell_error != 0
    silent! colorscheme default
    return
  endif
  let l:force = a:0 ? a:1 : 0
  let l:theme = exists('$DOTFILES_THEME_VIM_RESOLVED') ? $DOTFILES_THEME_VIM_RESOLVED : ''
  if l:force || empty(l:theme)
    let l:theme = trim(system(shellescape($DOTFILES_DIR . '/bin/theme-switcher') . ' resolve vim'))
    let $DOTFILES_THEME_VIM_RESOLVED = l:theme
  endif
  let l:file = $DOTFILES_DIR . '/themes/' . l:theme . '/vim.vim'
  if !filereadable(l:file)
    echoerr 'Theme file not found: ' . l:file
    return
  endif

  let l:scheme = s:ThemeColorScheme(l:file)
  let g:dotfiles_theme_fallback = 0
  let g:dotfiles_theme_fallback_scheme = ''
  if !empty(l:scheme) && empty(globpath(&runtimepath, 'colors/' . l:scheme . '.vim'))
    silent! colorscheme default
    let g:dotfiles_theme_fallback = 1
    let g:dotfiles_theme_fallback_scheme = l:scheme
  else
    execute 'source ' . fnameescape(l:file)
  endif
  let l:p = s:ThemePalette(l:theme)
  if !empty(l:p)
    " Informational text meets the 4.5:1 target; borders remain free to be
    " quieter because they are decorative rather than the only cue.
    execute 'highlight Comment guifg=' . l:p.secondary . ' cterm=italic gui=italic'
    execute 'highlight LineNr guifg=' . l:p.secondary
    execute 'highlight Search guifg=' . l:p.bg . ' guibg=' . l:p.yellow . ' cterm=bold gui=bold'
    execute 'highlight IncSearch guifg=' . l:p.bg . ' guibg=' . l:p.accent . ' cterm=bold gui=bold'
    execute 'highlight Visual guifg=' . l:p.fg . ' guibg=' . l:p.surface

    let g:dotfiles_airline_bg = l:p.bg
    let g:dotfiles_airline_fg = l:p.fg
    let g:dotfiles_airline_secondary = l:p.secondary
    let g:dotfiles_airline_surface = l:p.surface
    let g:dotfiles_airline_accent = l:p.accent
    let g:dotfiles_airline_accent2 = l:p.accent2
    let g:dotfiles_airline_red = l:p.red
    let g:airline_theme = 'dotfiles'
    if exists(':AirlineTheme') == 2
      silent! AirlineTheme dotfiles
    endif
  endif
endfunction

command! ThemeReload call DotfilesThemeReload(1)
call DotfilesThemeReload(0)
