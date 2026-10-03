" dotfiles colorscheme. Uses only palette indices, never RGB: ANSI 0-15 plus
" the role slots that bin/theme-switcher maps per tmux window (235 surface,
" 238 selection, 240 border, 245 secondary, 22/28 added, 52/88 removed). A
" theme change in tmux therefore recolors running editors too. Requires
" 'notermguicolors'.

hi clear
if exists('syntax_on')
  syntax reset
endif
let g:colors_name = 'dotfiles'

function! s:hi(group, fg, bg, attr) abort
  execute 'hi' a:group 'ctermfg=' . a:fg 'ctermbg=' . a:bg 'cterm=' . a:attr
endfunction

" Editor text
call s:hi('Normal',       'NONE', 'NONE', 'NONE')
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
