# Minimal Vim Configuration - Quick Reference

## Philosophy
Use VS Code for development, vim for quick edits. This minimal config starts in <50ms.

## Included Plugins (5 Essential Only)
- **vim-surround**: `cs"'` change surrounding quotes, `ds"` delete surrounds
- **vim-commentary**: `gcc` comment line, `gc{motion}` comment motion
- **vim-repeat**: Makes `.` work with plugin commands
- **vim-fugitive**: `:Git` for git status, `:Gdiffsplit` for diffs
- **Nord theme**: Clean, minimal colorscheme

## Leader Key: `,` (comma)

### Essential Shortcuts
| Key | Action |
|-----|--------|
| `,w` | Save file |
| `,q` | Quit |
| `,x` | Save and quit |
| `,<space>` | Clear search highlighting |

### ESDF Navigation (Your Custom Setup)
| Key | Action |
|-----|--------|
| `Ctrl+E` | Move to window above |
| `Ctrl+S` | Move to window left |
| `Ctrl+D` | Move to window below |
| `Ctrl+F` | Move to window right |
| `Alt+A` | Previous tab |
| `Alt+G` | Next tab |

### Git Commands
| Key | Action |
|-----|--------|
| `,gs` | Git status |
| `,gd` | Git diff split |
| `,gb` | Git blame |

### Better Defaults
| Key | Action |
|-----|--------|
| `Y` | Yank to end of line |
| `n/N` | Search with centered cursor |
| `Q` | Quick macro replay (@q) |

### Toggles
| Key | Action |
|-----|--------|
| `,n` | Toggle relative line numbers |
| `,z` | Toggle line wrapping |

## Switching Between Configs
```bash
vim-minimal  # Switch to this fast config
vim-full     # Switch to full-featured config
vim-status   # Check current config
```

## When to Use Minimal vs Full

**Use Minimal Config For:**
- Quick edits to config files
- Git commit messages
- Reading logs or text files
- Any edit under 5 minutes

**Use Full Config For:**
- Extended terminal coding sessions
- When you need language servers
- File fuzzy finding
- Multiple file projects

**Use VS Code For:**
- Main development work
- Debugging
- Multi-file refactoring
- Anything requiring IntelliSense