" dotfiles colorscheme. Colors are palette indices: ANSI 0-15 plus the role
" slots that bin/theme-switcher maps per tmux window (235 surface, 238
" selection, 240 border, 245 secondary, 22/28 added, 52/88 removed).
"
" Following (the default) uses the indices themselves with 'notermguicolors',
" so a theme change in tmux recolors running editors too. When pinned
" (g:dotfiles_nvim_theme, set by :Theme), each index becomes that theme's RGB
" value with 'termguicolors', and the editor paints its own canvas.

let s:palette = dotfiles#theme#palette(get(g:, 'dotfiles_nvim_theme', ''))
let s:pinned = !empty(s:palette)
let &termguicolors = s:pinned
if s:pinned
  let s:bg = s:palette.bg
  let &background = str2nr(s:bg[1:2], 16) + str2nr(s:bg[3:4], 16) + str2nr(s:bg[5:6], 16) > 384 ? 'light' : 'dark'
endif

hi clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = 'dotfiles'

" fg/bg are 'fg' and 'bg' for the canvas, a palette index, or NONE.
function! s:hi(group, fg, bg, attr) abort
  let l:cmd = ['hi', a:group, 'cterm=' . a:attr, 'gui=' . a:attr]
  for [l:key, l:value] in [['fg', a:fg], ['bg', a:bg]]
    call add(l:cmd, 'cterm' . l:key . '=' . (l:value =~# '^\d\+$' ? l:value : 'NONE'))
    call add(l:cmd, 'gui' . l:key . '=' . get(s:palette, l:value, 'NONE'))
  endfor
  execute join(l:cmd)
endfunction

" :terminal buffers use the pinned theme's ANSI colors too.
for s:i in range(16)
  if s:pinned
    let g:terminal_color_{s:i} = s:palette[string(s:i)]
  elseif exists('g:terminal_color_' . s:i)
    unlet g:terminal_color_{s:i}
  endif
endfor

" Editor text
call s:hi('Normal',       'fg',   'bg',   'NONE')
call s:hi('Comment',      '245',  'NONE', 'italic')
call s:hi('Constant',     '3',    'NONE', 'NONE')
call s:hi('String',       '2',    'NONE', 'NONE')
call s:hi('Character',    '2',    'NONE', 'NONE')
call s:hi('Identifier',   'NONE', 'NONE', 'NONE')
call s:hi('Function',     '4',    'NONE', 'NONE')
call s:hi('Statement',    '5',    'NONE', 'NONE')
call s:hi('Operator',     'NONE', 'NONE', 'NONE')
call s:hi('PreProc',      '6',    'NONE', 'NONE')
call s:hi('Type',         '3',    'NONE', 'NONE')
call s:hi('Special',      '6',    'NONE', 'NONE')
call s:hi('Delimiter',    'NONE', 'NONE', 'NONE')
call s:hi('Underlined',   '4',    'NONE', 'underline')
call s:hi('Error',        '1',    'NONE', 'bold')
call s:hi('Todo',         '3',    'NONE', 'bold')
call s:hi('Title',        '4',    'NONE', 'bold')
call s:hi('Directory',    '4',    'NONE', 'NONE')

" Editor chrome
call s:hi('LineNr',       '245',  'NONE', 'NONE')
call s:hi('CursorLineNr', 'NONE', 'NONE', 'bold')
call s:hi('CursorLine',   'NONE', '235',  'NONE')
call s:hi('CursorColumn', 'NONE', '235',  'NONE')
call s:hi('ColorColumn',  'NONE', '235',  'NONE')
call s:hi('SignColumn',   'NONE', 'NONE', 'NONE')
call s:hi('FoldColumn',   '245',  'NONE', 'NONE')
call s:hi('Folded',       '245',  '235',  'NONE')
call s:hi('WinSeparator', '240',  'NONE', 'NONE')
call s:hi('StatusLine',   'NONE', '235',  'NONE')
call s:hi('StatusLineNC', '245',  '235',  'NONE')
call s:hi('TabLine',      '245',  '235',  'NONE')
call s:hi('TabLineFill',  'NONE', '235',  'NONE')
call s:hi('TabLineSel',   'NONE', 'NONE', 'bold')
call s:hi('Pmenu',        'NONE', '235',  'NONE')
call s:hi('PmenuSel',     'NONE', '238',  'bold')
call s:hi('PmenuSbar',    'NONE', '238',  'NONE')
call s:hi('PmenuThumb',   'NONE', '240',  'NONE')
call s:hi('NormalFloat',  'NONE', '235',  'NONE')
call s:hi('FloatBorder',  '240',  '235',  'NONE')
call s:hi('Visual',       'NONE', '238',  'NONE')
call s:hi('QuickFixLine', 'NONE', '238',  'NONE')
call s:hi('MatchParen',   'NONE', '238',  'bold')
call s:hi('NonText',      '240',  'NONE', 'NONE')
call s:hi('Whitespace',   '240',  'NONE', 'NONE')
call s:hi('SpecialKey',   '240',  'NONE', 'NONE')
" Reverse draws the text in the window's background color on the accent.
call s:hi('Search',       '3',    'NONE', 'reverse,bold')
call s:hi('CurSearch',    '4',    'NONE', 'reverse,bold')
call s:hi('IncSearch',    '4',    'NONE', 'reverse,bold')
call s:hi('ModeMsg',      'NONE', 'NONE', 'bold')
call s:hi('MoreMsg',      '2',    'NONE', 'NONE')
call s:hi('Question',     '2',    'NONE', 'NONE')
call s:hi('WarningMsg',   '3',    'NONE', 'NONE')
call s:hi('ErrorMsg',     '1',    'NONE', 'bold')

" Diffs and version control
call s:hi('DiffAdd',      'NONE', '22',   'NONE')
call s:hi('DiffDelete',   '1',    '52',   'NONE')
call s:hi('DiffChange',   'NONE', '235',  'NONE')
call s:hi('DiffText',     'NONE', '238',  'bold')
call s:hi('Added',        '2',    'NONE', 'NONE')
call s:hi('Changed',      '3',    'NONE', 'NONE')
call s:hi('Removed',      '1',    'NONE', 'NONE')
hi! link GitGutterAdd Added
hi! link GitGutterChange Changed
hi! link GitGutterDelete Removed
hi! link GitGutterChangeDelete Changed

" Diagnostics and spelling
call s:hi('DiagnosticError',          '1', 'NONE', 'NONE')
call s:hi('DiagnosticWarn',           '3', 'NONE', 'NONE')
call s:hi('DiagnosticInfo',           '4', 'NONE', 'NONE')
call s:hi('DiagnosticHint',           '6', 'NONE', 'NONE')
call s:hi('DiagnosticOk',             '2', 'NONE', 'NONE')
call s:hi('DiagnosticUnderlineError', 'NONE', 'NONE', 'undercurl')
call s:hi('DiagnosticUnderlineWarn',  'NONE', 'NONE', 'undercurl')
call s:hi('DiagnosticUnderlineInfo',  'NONE', 'NONE', 'underline')
call s:hi('DiagnosticUnderlineHint',  'NONE', 'NONE', 'underline')
call s:hi('SpellBad',                 'NONE', 'NONE', 'undercurl')
call s:hi('SpellCap',                 'NONE', 'NONE', 'underline')
call s:hi('SpellRare',                'NONE', 'NONE', 'underline')
call s:hi('SpellLocal',               'NONE', 'NONE', 'underline')
hi! link ALEErrorSign DiagnosticError
hi! link ALEWarningSign DiagnosticWarn
