# Advanced Vim Usage Guide: From Standard Vim to Power User

This guide helps you transition from standard Vim to the advanced Neovim configuration in this dotfiles repository. Learn to leverage powerful plugins, custom keybindings, and modern workflows.

## Table of Contents
1. [Key Differences from Standard Vim](#key-differences)
2. [Essential Keybindings](#essential-keybindings)
3. [File Navigation with FZF](#file-navigation)
4. [Git Integration](#git-integration)
5. [Code Intelligence](#code-intelligence)
6. [Text Manipulation](#text-manipulation)
7. [Theme Management](#theme-management)
8. [Practical Workflows](#practical-workflows)

## Key Differences from Standard Vim

### 1. Window Navigation
**Standard Vim**: `Ctrl+W` then `hjkl`  
**This Config**: `Ctrl+ESDF` (directly, no prefix needed!)

```
Ctrl+E = Move to window above
Ctrl+S = Move to window left
Ctrl+D = Move to window below
Ctrl+F = Move to window right
```

Why ESDF? It's more ergonomic than hjkl and doesn't require moving from home row.

### 2. Leader Key
**Standard Vim**: `\` (backslash)  
**This Config**: `,` (comma)

Much easier to reach! All custom commands use `,` as prefix.

### 3. Escape Alternative
**Standard Vim**: Only `Esc`  
**This Config**: `jk` (in insert mode)

Type `jk` quickly to exit insert mode - no reaching for Esc!

### 4. Search Clearing
**Standard Vim**: `:noh<Enter>`  
**This Config**: `Space` (in normal mode)

Just hit spacebar to clear search highlights.

## Essential Keybindings

### File Operations
- `,w` - Save file (force)
- `,q` - Quit
- `,Q` - Quit all (force)

### Navigation Enhancements
- `Shift+Up` - Half page up
- `Shift+Down` - Half page down
- `,n` - Toggle line numbers on/off

## File Navigation with FZF

### The Game Changer: Fuzzy Finding
Forget `:e` and file paths. FZF changes everything:

#### Quick File Access
- `Ctrl+P` or `,f` - Find files
  - Type partial filenames: `contjs` finds `controllers.js`
  - Use spaces for multiple terms: `user model` finds `user_model.rb`

#### Buffer Management
- `,b` - Switch between open files
  - Shows preview of each file
  - Fuzzy search through buffer names

#### Content Search
- `,g` - Ripgrep search (like grep but faster)
  - Search entire codebase: `,g` then type `TODO`
  - Case-sensitive: `,g` then `TODO` (with caps)

### FZF Pro Tips
1. **Preview Window**: `Ctrl+/` toggles preview
2. **Multiple Selection**: `Tab` to select multiple files
3. **Path Matching**: `src/user` matches paths containing both terms

## Git Integration

### Fugitive (Main Git Operations)
- `,gs` - Git status (interactive)
  - Press `-` on a file to stage/unstage
  - Press `Enter` to view file
  - Press `cc` to commit
- `,gd` - Git diff current file (split view)
- `,gc` - Git commit
- `,gb` - Git blame (see who wrote each line)

### GitGutter (Visual Git Info)
See changes in the sign column:
- `+` for added lines
- `~` for modified lines
- `-` for removed lines

#### Hunk Navigation
- `,hn` - Next change
- `,hp` - Previous change
- `,hs` - Stage current change
- `,hu` - Undo current change

### Example Git Workflow
```vim
,gs          " Check status
,hn          " Jump to next change
,hs          " Stage that change
,hn ,hs      " Stage next change
,gc          " Commit changes
```

## Code Intelligence

### ALE (Asynchronous Lint Engine)
Real-time error checking without saving!

#### Navigation
- `,an` - Next error/warning
- `,ap` - Previous error/warning
- `,af` - Auto-fix current file

#### Visual Indicators
- `●` in gutter = Error
- `.` in gutter = Warning
- Bottom status shows error details

### Language-Specific Features
The config auto-detects and configures:
- **Python**: Ruff linting, Black formatting
- **JavaScript/TypeScript**: ESLint, Prettier
- **YAML/JSON**: 2-space indents

## Text Manipulation

### Surround (Change Quotes/Brackets)
- `cs"'` - Change double quotes to single: `"hello"` → `'hello'`
- `cs'<q>` - Change to HTML quotes: `'hello'` → `<q>hello</q>`
- `ds"` - Delete surrounding quotes: `"hello"` → `hello`
- `ysiw"` - Add quotes around word: `hello` → `"hello"`

### Commentary
- `,/` - Toggle comment (works in visual mode too!)
- `gc` + motion - Comment specific area
  - `gcap` - Comment paragraph
  - `gc3j` - Comment 3 lines down

### Auto-Pairs
Brackets auto-close as you type:
- Type `(` get `()`
- Type `{` get `{}`
- Type `[` get `[]`

## Theme Management

### Quick Theme Switching
Exit vim and run:
```bash
./bin/theme-switcher
```

Available themes:
1. Gruvbox Material (default)
2. Nord
3. Tokyo Night
4. Kanagawa
5. Catppuccin Mocha

Theme changes persist across sessions!

## Practical Workflows

### 1. Quick Code Review
```vim
,g TODO              " Find all TODOs
,gs                  " Check git status
,gb                  " See who wrote current line
```

### 2. Refactoring Session
```vim
,g oldFunctionName   " Find all occurrences
,b                   " Switch between files
cs"'                 " Change quotes
,af                  " Auto-fix formatting
```

### 3. Debugging Session
```vim
,an                  " Jump to next error
,gd                  " See what changed
,hu                  " Undo problematic change
```

### 4. File Explorer Alternative
Instead of NERDTree:
```vim
,f                   " Fuzzy find files
:e .                 " Browse current directory
:E                   " Explore in split
```

### 5. Multi-File Editing
```vim
,f                   " Find first file
Ctrl+P               " Find second file
:sp                  " Split window
Ctrl+E/D             " Navigate between splits
```

## Power User Tips

### 1. Persistent Undo
Your undo history survives restarts! Made changes yesterday? Just keep pressing `u`.

### 2. System Clipboard
Everything uses system clipboard by default:
- Yank in vim → Paste anywhere
- Copy outside → Paste in vim

### 3. Visual Selection
After yanking, the selection briefly highlights - no more guessing what you copied!

### 4. Smart Case Search
- `/hello` - Case insensitive
- `/Hello` - Case sensitive (capital triggers it)

### 5. File Path Completion
- Type `:e src/` then `Tab` - autocompletes paths
- Works with `**` for recursive: `:e **/user.js<Tab>`

## Common Gotchas & Solutions

### "Why isn't my theme working?"
Run the theme switcher script, don't manually edit config.

### "How do I install a new plugin?"
1. Add to `init.vim` between `plug#begin` and `plug#end`
2. Restart vim
3. Run `:PlugInstall`

### "How do I update plugins?"
Run `:PlugUpdate` inside vim

### "My Python isn't formatting"
Ensure you have the tools:
```bash
pip install --user black ruff
```

### "FZF preview not working?"
Install bat for syntax highlighting:
```bash
sudo apt install bat
```

## Quick Reference Card

```
Navigation          Git                 Code
---------          ---                 ----
Ctrl+P  Files      ,gs  Status        ,af  Fix
,b      Buffers    ,gd  Diff          ,an  Next err
,g      Grep       ,gb  Blame         ,ap  Prev err
,f      Files      ,hn  Next hunk     ,/   Comment
Space   Clear hl   ,hs  Stage hunk    

Windows            Text                Settings
-------            ----                --------
Ctrl+E  Up         cs"' Change quotes  ,n   Line nums on/off
Ctrl+S  Left       ds"  Delete quotes  ,ss  Strip space
Ctrl+D  Down       ysiw" Add quotes    ,w   Save
Ctrl+F  Right      ,/   Comment        ,q   Quit
```

## Next Steps

1. **Practice FZF**: It's the biggest productivity boost
2. **Learn Fugitive**: `,gs` is incredibly powerful
3. **Master Surround**: `cs`, `ds`, `ys` will save hours
4. **Use GitGutter**: Visual git info is invaluable

Remember: You don't need to learn everything at once. Start with file navigation (Ctrl+P) and build from there!