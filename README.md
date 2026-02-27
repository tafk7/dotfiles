# Dotfiles — Ubuntu Development Environment

Tiered dotfiles system for Ubuntu/WSL. Install only what you need: from config-only (no sudo) to complete development environment.

## Quick Start

```bash
./setup.sh --config              # Symlinks only (no sudo)
./setup.sh --shell               # + starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, direnv
./setup.sh --dev                 # + neovim, lazygit, tmux
./setup.sh --full                # + NVM, pyenv, uv, poetry, Docker, Azure CLI
./setup.sh --shell --dry-run     # Preview without changes
```

Each tier includes all previous tiers. Use `--force` to overwrite without prompting.

After installation, verify with `./bin/verify` and restart your shell.

## What You Get

### Modern CLI Replacements

| Classic | Modern | Alias |
|---------|--------|-------|
| `ls` | eza | `ll`, `la`, `l`, `tree` |
| `cat` | bat | `view` |
| `find` | fd | — |
| `grep` | ripgrep | — |
| `cd` | zoxide | `z`, `zi` |
| `diff` | delta | (auto via git) |
| `top` | btop | `top` |

### Shell & Navigation

```bash
reload                    # Reload shell configuration
mkcd <dir>                # Create directory and cd into it
proj                      # Interactive project finder (FZF)
psg <name>                # Search running processes
extract <archive>         # Universal archive extraction
```

### Git

```bash
# Aliases (g + command abbreviation)
gs / ga / gc / gd         # status / add / commit / diff
gsw / gswc / gb           # switch / switch -c / branch
gp / gpl / gf             # push / pull / fetch
gst / gstp                # stash / stash pop
lg                        # lazygit TUI

# FZF-enhanced (f prefix)
fgb                       # Interactive branch switcher
fgl                       # Interactive commit browser
frg                       # Interactive ripgrep search
```

### Python

```bash
pyset 3.11.9              # Set project Python + create .venv
pyset --default 3.11.9    # Set global default
vactivate                 # Manual venv activation
pyinfo                    # Show environment info
pylist                    # List installed versions

# uv shortcuts
uvs / uvr / uva / uvpi    # sync / run / add / pip install

# direnv auto-activation (recommended)
echo 'layout pyenv 3.11.9' > .envrc && direnv allow
```

### VS Code

```bash
c                         # Open current directory
cf                        # FZF file search → open in VS Code
cproj                     # FZF project search → open in VS Code
cdiff <a> <b>             # Diff two files in VS Code
```

### Docker

```bash
dps / dpsa                # ps / ps -a
dc / dcu / dcd / dcl      # compose / up -d / down / logs
denter <id>               # Exec into container (bash or sh)
dstopall                  # Stop all running containers
```

### Node.js

```bash
ni / nr / nrd / nrb       # install / run / run dev / run build
nclean                    # rm node_modules + reinstall
```

### Tmux

```bash
tm <name> / ta <name>     # New session / attach
tl / tk <name>            # List / kill session
tmux-minimal / tmux-full  # Switch config mode
```

### WSL (auto-detected)

```bash
pbcopy / pbpaste          # Clipboard integration
sync-ssh                  # Import SSH keys from Windows
cdwin / cddesk / cddl     # Navigate to Windows directories
open / explorer           # Open in Windows Explorer
```

## Theme System

Five unified themes applied simultaneously to neovim, tmux, and shell (FZF):

```bash
./bin/theme-switcher              # Interactive FZF selection
./bin/theme-switcher nord         # Direct switch
./bin/theme-switcher --preview tokyo-night
./bin/theme-switcher --revert     # Revert to previous
./bin/theme-switcher --list       # Show available themes
```

**Available:** Nord, Kanagawa, Tokyo Night, Gruvbox Material, Catppuccin Mocha

## Architecture

```
setup.sh                  Entry point — 3-phase orchestrator (reads lib/config.sh)
lib/
  install.sh              Install-time helpers (APT, backup, eget, tier functions)
  runtime.sh              Runtime helpers (logging, is_wsl, verify_binary)
  config.sh               Declarative data: CONFIG_MAP + PACKAGES
configs/                  Config files without dots (symlinked to ~/.<name>)
themes/                   5 theme directories, each with colors.sh, vim.vim, tmux.conf, shell.sh
shell/
  shared.sh               Single sourcing sequence for bash + zsh
  bash.sh / zsh.sh        Shell-specific config → ~/.bashrc / ~/.zshrc
  profile.sh              Login shell → ~/.profile
  env.sh                  Environment: PATH, pyenv, direnv, EDITOR, WSL vars
  nvm-lazy.sh             Lazy NVM loader for both shells
  functions/*.sh          Domain-split functions (nav, process, python, fzf, wsl, tmux, docker, git)
  aliases/*.sh            9 alias categories (general, git, docker, python, node, vim, vscode, wsl, claude)
installers/               Per-tool install scripts
bin/                      User commands (theme-switcher, verify, cheatsheet, replace, vim/tmux-config-switcher)
```

**Shell startup** (`~/.bashrc` or `~/.zshrc`) sources: `shared.sh` → `env.sh` → theme → `fzf.sh` → `functions/*.sh` → `aliases/*.sh` → `~/.shell.local` → shell-specific (prompt, completion, nvm-lazy).

## Extending

**New tool:** Create `installers/install-<tool>.sh`, wire in `lib/install.sh` tier function, add aliases to `shell/aliases/`, add cheatsheet entries to `shell/shortcuts-index.tsv`.

**New config:** Add file to `configs/`, add to `CONFIG_MAP` in `lib/config.sh`.

**New theme:** Create `themes/<name>/` with `colors.sh`, `vim.vim`, `tmux.conf`, `shell.sh`. Register in `THEMES` array in `bin/theme-switcher`.

**Local overrides:** `~/.shell.local` and `~/.bashrc.local` / `~/.zshrc.local` are sourced last and not tracked.

## Troubleshooting

```bash
./bin/verify                      # Validate installation
./setup.sh --dry-run --shell      # Preview what would happen
reload                            # Reload shell config
ls .backups/                      # See available backups
```
