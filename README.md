# Dotfiles - Ubuntu Development Environment

Streamlined, tiered dotfiles management system for Ubuntu/WSL. Install only what you need: from config-only (no sudo) to complete development environment.

## Quick Start

```bash
# Config only - just symlinks, no installs
./setup.sh --config

# Modern shell - add starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, direnv
./setup.sh --shell

# Development tools - add neovim, lazygit, tmux, Claude Code
./setup.sh --dev

# Complete environment - add NVM, pyenv, uv, poetry, Docker, Azure CLI
./setup.sh --full

# Everything including media tools
./setup.sh --full --personal
```

## Architecture Overview

### Directory Structure
```
dotfiles/
├── setup.sh              # Entry point - orchestrates installation
├── lib.sh                # Utilities library
│
├── configs/              # Visible config files (symlinked to ~/.* locations)
│   ├── bashrc, zshrc     # Shell configurations
│   ├── init.vim          # Neovim config
│   ├── tmux.conf         # Terminal multiplexer
│   ├── gitconfig         # Template (prompts for user info)
│   ├── starship.toml     # Modern prompt config
│   └── themes/           # Unified theme system
│       ├── nord/
│       ├── kanagawa/
│       ├── tokyo-night/
│       ├── gruvbox/
│       └── catppuccin/
│
├── shell/                # Runtime integration (auto-loaded at startup)
│   ├── env.sh            # Environment variables (NVM, pyenv, FZF)
│   ├── functions.sh      # Core utilities (extract, psg, mkcd, proj)
│   ├── wsl-functions.sh  # WSL-specific utilities
│   └── aliases/          # Organized by category
│       ├── general.sh    # Modern CLI replacements
│       ├── docker.sh     # Container shortcuts
│       ├── git.sh        # Git workflow
│       ├── python.sh     # Python development
│       ├── node.sh       # Node.js aliases
│       └── wsl.sh        # Windows integration
│
├── install/              # Dedicated installers for modern tools
│   ├── install-starship.sh
│   ├── install-eza.sh
│   ├── install-delta.sh
│   ├── install-btop.sh
│   ├── install-uv.sh
│   ├── install-neovim.sh
│   ├── install-pyenv.sh
│   └── install-nvm.sh
│
└── bin/                  # User commands
    ├── theme-switcher    # Interactive theme management
    ├── vim-config-switcher   # Switch vim minimal/full
    ├── tmux-config-switcher  # Switch tmux minimal/full
    ├── check-setup       # Validate installation
    └── cheatsheet        # Interactive command reference
```

### Core Components

**setup.sh** - Entry point and orchestrator
- Parses CLI arguments (`--config`, `--shell`, `--dev`, `--full`)
- Orchestrates 3-phase installation:
  1. System verification (Ubuntu version, WSL detection)
  2. Package installation (tier-based)
  3. Configuration setup (symlinks, templates, WSL integration)

**lib.sh** - Consolidated utilities library
- Logging and output formatting
- WSL detection and integration
- Backup management
- Package installation (tier-based)
- Security functions (safe_sudo, HTTPS-only downloads)

## Installation Tiers

The system uses **cumulative tiers** - each tier includes all previous tiers:

| Tier | What It Installs | Sudo Required? |
|------|------------------|----------------|
| **config** | Symlinks only (zero installs) | No |
| **shell** | + Modern CLI tools (starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, direnv) | Yes |
| **dev** | + Development tools (neovim, lazygit, tmux, Claude Code) | Yes |
| **full** | + Complete environment (NVM, pyenv, uv, poetry, Docker, Azure CLI) | Yes |

**Modifiers:**
- `--personal` - Add media tools (ffmpeg, yt-dlp) to any tier
- `--force` - Overwrite existing configs without prompting
- `--dry-run` - Preview actions without making changes

## Key Features

### 1. Visible Configuration Files
All configs stored **without leading dots** for discoverability:
```
configs/bashrc       → ~/.bashrc
configs/zshrc        → ~/.zshrc
configs/init.vim     → ~/.config/nvim/init.vim
configs/gitconfig    → ~/.gitconfig (template processed)
```
**Benefits:** Tab completion works, easy to browse, still symlinked to expected locations.

### 2. Unified Theme System
Switch themes across vim/tmux/shell simultaneously:
```bash
./bin/theme-switcher              # Interactive FZF selection
./bin/theme-switcher nord         # Direct switch
./bin/theme-switcher --preview    # Preview before applying
```
**Available themes:** Nord, Kanagawa, Tokyo Night, Gruvbox Material, Catppuccin Mocha

Each theme provides:
- `colors.sh` - RGB palette definitions
- `shell.sh` - FZF and terminal colors
- `vim.vim` - Neovim colorscheme
- `tmux.conf` - Status bar and pane colors

### 3. WSL Integration
Seamless Windows ↔ Linux integration (auto-detected):
```bash
pbcopy / pbpaste    # Clipboard integration
sync-ssh            # Import SSH keys from Windows
winget              # Access Windows package manager
```

### 4. Modern CLI Tools
Replaces traditional Unix tools with modern alternatives:
- `ls` → `eza`
- `cat` → `bat`
- `find` → `fd`
- `grep` → `ripgrep`
- `cd` → `zoxide`
- `diff` → `delta` (syntax-highlighted git diffs)
- `top` → `btop` (modern resource monitor)
- `pip install` → `uv pip install` (fast Python package manager)

### 5. Python Development Workflow
Advanced pyenv + uv integration with direnv auto-activation:
```bash
pyset --default 3.11.9    # Set global default Python
pyset 3.11.9              # Set project Python + create .venv (uses uv when available)
vactivate                 # Manual venv activation
pyinfo                    # Show environment info (pyenv, uv, direnv status)

# direnv auto-activation (recommended)
echo 'layout pyenv 3.11.9' > .envrc && direnv allow

# uv shortcuts
uvs                       # uv sync
uvr pytest                # uv run <command>
uvpi requests             # uv pip install <package>
```

### 6. Performance Optimizations
- Starship prompt (fast startup)
- Lazy-load NVM (loads on first use)
- Optional minimal configs for vim/tmux

## Runtime Commands

After installation, these commands become available:

### Shell & Navigation
```bash
reload        # Reload shell configuration
psg <name>    # Search running processes
mkcd <dir>    # Create directory and cd into it
proj          # Interactive project finder (searches ~/projects, ~/dev, etc.)
z <dir>       # Smart directory jumping (zoxide)
zi            # Interactive directory search
```

### Development Tools
```bash
# Git (enhanced with FZF)
gb            # Interactive git branch switcher
gl            # Interactive git log browser
lg            # Visual git interface (lazygit)

# Python
pyset         # Set Python version for project
vactivate     # Manual venv activation
pyinfo        # Show Python environment info
pylist        # List installed Python versions
uvs / uvr     # uv sync / uv run

# Node.js
nvm           # Node Version Manager
ni            # npm install
nr            # npm run
```

### VS Code Integration
```bash
c             # Open current directory in VS Code
cf            # Find file with fzf and open in VS Code
cgrep         # Search content and open at line in VS Code
```

### System Management
```bash
./bin/theme-switcher           # Switch themes interactively
./bin/check-setup              # Validate installation
./bin/cheatsheet               # Interactive command reference
./setup.sh --config            # Refresh config symlinks
vim-minimal / vim-full         # Switch vim configurations
tmux-minimal / tmux-full       # Switch tmux configurations
```

### WSL-Specific
```bash
sync-ssh      # Import SSH keys from Windows
pbcopy        # Copy to Windows clipboard
pbpaste       # Paste from Windows clipboard
```

## Extension Guide

### Adding New Packages
**Base packages** (installed with `--shell` or higher):
```bash
# Edit lib.sh, add to PACKAGES array
declare -A PACKAGES=(
    [core]="git build-essential"
    [modern]="bat fd-find ripgrep fzf your-new-package"
    ...
)
```

**Tier-specific packages**:
```bash
# Edit appropriate function in lib.sh
install_shell_packages() {
    # Add your package here
}
```

### Adding New Configurations
```bash
# 1. Create config file in configs/ (no leading dot)
configs/your-config

# 2. Add mapping to setup.sh
declare -A CONFIG_MAP=(
    [your-config]="$HOME/.your-config:symlink"
)
```

### Adding Aliases or Functions
```bash
# Aliases: Create file in shell/aliases/
shell/aliases/your-category.sh

# Functions: Add to shell/functions.sh
your_function() {
    # Implementation
}
```

### Adding New Themes
```bash
# 1. Create theme directory
configs/themes/your-theme/

# 2. Add required files
├── colors.sh      # RGB palette definitions
├── shell.sh       # FZF and terminal colors
├── vim.vim        # Neovim colorscheme
└── tmux.conf      # Status bar colors

# 3. Update bin/theme-switcher
declare -A THEMES=(
    ["your-theme"]="Your Theme - Description"
)
```

## Design Principles

1. **Ubuntu-Only** - No cross-platform complexity
2. **Human-Readable** - Clear naming, extensive comments
3. **Tiered Installation** - Install only what you need
4. **Non-Destructive** - Automatic backups before changes
5. **Visible Configs** - Files stored without leading dots
6. **Security-First** - HTTPS-only downloads, input validation
7. **Performance** - Lazy loading, fast prompt, optional minimal configs

## Security Features

- Shows commands before sudo execution
- Automatic backups before changes
- HTTPS-only external downloads
- Input validation (email format, etc.)
- Fail-fast error handling
- Proper SSH key permissions

## Troubleshooting

**Installation fails:**
```bash
./bin/check-setup           # Validate system requirements
./setup.sh --dry-run        # Preview without making changes
```

**Config not loading:**
```bash
reload                      # Reload shell configuration
source ~/.bashrc            # Manually source (bash)
source ~/.zshrc             # Manually source (zsh)
```

**Restore from backup:**
```bash
ls -la .backups/            # List available backups
cp .backups/backup-*/bashrc ~/.bashrc    # Restore specific file
```

**Theme not applying:**
```bash
./bin/theme-switcher --current     # Check current theme
./bin/theme-switcher nord          # Reapply theme
```

## Documentation

- **README.md** (this file) - Quick start and architecture overview
- **docs/architecture.md** - Detailed technical architecture
- **docs/theme-system.md** - Theme system documentation
- **docs/customization.md** - Extension guide

---

*Ubuntu/WSL development environment management system. Tiered installation, unified themes, modern CLI tools.*