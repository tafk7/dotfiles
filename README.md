# Dotfiles - Simplified Ubuntu Development Environment

A streamlined, human-readable dotfiles management system for Ubuntu environments (including WSL). Focused on simplicity, maintainability, and essential development tools.

## 🎯 Key Features

- **🚀 Simplified Architecture** - Modular design with clear separation of concerns
- **🔒 Security-First** - HTTPS-only downloads, checksum verification, safe operations  
- **🐧 Ubuntu Focused** - Optimized for Ubuntu/WSL, no cross-platform complexity
- **✅ Validation System** - Pre/post installation checks ensure everything works
- **🔄 Non-Destructive** - Automatic backups before any changes
- **👀 Visible Configs** - No hidden source files, easy to discover and edit
- **📝 Template Support** - Dynamic configuration (e.g., Git user setup)

## 🚀 Quick Start

```bash
# Base installation (essential tools + Docker)
./setup.sh

# Add work tools (Azure CLI, Node.js/Python dev tools)
./setup.sh --work

# Add personal tools (media applications)
./setup.sh --personal

# Everything
./setup.sh --work --personal

# Force mode for existing installations
./setup.sh --force          # Backup and replace existing files
```

## 📦 What You Get

### Base Installation (Always)

**Essential Tools:**
- Build tools: build-essential, curl, wget, git, zip/unzip, jq
- Modern shell: zsh with Starship prompt for fast, visual experience
- Modern CLI replacements: eza (includes tree functionality), bat, fd-find, ripgrep, fzf
- Development basics: Python 3, pip, pipx
- **Docker**: Container platform with user group setup
- **Theme System**: 5 pre-configured color schemes (Nord, Tokyo Night, Kanagawa, Gruvbox Material, Catppuccin)

**Configuration Files:**
- Shell configs: `.bashrc`, `.zshrc`, `.profile` with theme support
- Development: `init.vim` (vim-plug + 18 plugins), `.tmux.conf` (TPM + plugins), `.gitconfig`, `.editorconfig`
- Tool configs: `.ripgreprc`, bat, fd configurations
- Theme configs: Unified color schemes for neovim, tmux, shell, and FZF
- **VS Code Integration**: Optimized settings for hybrid vim/visual workflow

### Work Tools (`--work`)

**Professional Development:**
- **Azure CLI**: Ubuntu-specific installation for cloud development
- **Node.js via NVM**: Node Version Manager for flexible Node.js/npm management
- **Python via pyenv**: Python Version Manager for flexible Python version management, works with Poetry and pip projects

### Personal Tools (`--personal`)

**Media & Entertainment:**
- ffmpeg, yt-dlp

### WSL Integration (Automatic)

**Windows Subsystem for Linux:**
- Clipboard integration: `pbcopy` and `pbpaste` commands
- SSH key import from Windows SSH agent
- Windows username detection for cross-system operations
- WSL-specific packages: socat, wslu

## 🏗️ Simplified Architecture

The system is organized into modular components:

```
dotfiles/
├── setup.sh                      # Main installer
├── lib/
│   ├── core.sh                   # Core utilities and functions
│   └── packages.sh               # Package management
├── configs/                      # Visible config files (no leading dots!)
│   ├── bashrc, zshrc, init.vim  # Shell and editor configs
│   ├── tmux.conf, gitconfig     # Development tools
│   ├── config/                  # Additional config directories
│   └── themes/                   # Theme configurations
│       ├── nord/                 # Nord theme files
│       ├── tokyo-night/          # Tokyo Night theme files
│       └── ...                   # Other themes
├── bin/              # User commands
├── install/          # Installation scripts
├── shell/            # Shell integration
│   ├── env/                      # Environment variables
│   │   └── common.sh            # Shared environment setup
│   ├── aliases/                  # Shell aliases by category
│   │   ├── general.sh           # Common command aliases
│   │   ├── docker.sh            # Docker shortcuts
│   │   ├── git.sh               # Git aliases
│   │   └── wsl.sh               # WSL-specific aliases
│   ├── functions/                # Shared shell functions
│   │   └── shared.sh            # Common functions
│   └── theme-switcher.sh        # Interactive theme switcher
└── docs/                         # Documentation
```

## 🔧 Configuration Files

All config files are **visible** (no leading dots) for easy editing, but still symlink to the expected hidden locations:

- `configs/bashrc` → `~/.bashrc`
- `configs/zshrc` → `~/.zshrc`  
- `configs/init.vim` → `~/.config/nvim/init.vim`
- `configs/gitconfig` → `~/.gitconfig` (processed with your name/email)

**Benefits:**
- Tab completion works when editing configs
- Easy to find and modify
- Clear file organization
- Still work exactly as expected

## 🛠️ Runtime Commands

After installation, these commands are available:

```bash
# Reload shell configuration without restarting
reload

# Search for running processes  
psg <name>

# View markdown files with syntax highlighting
md <file>

# Switch terminal theme interactively
./bin/theme-switcher

# List available themes
themes

# WSL: Import SSH keys from Windows
sync-ssh

# WSL: Cross-platform clipboard
pbcopy / pbpaste

# VS Code shortcuts (after running install-vscode.sh)
c          # Open current directory in VS Code
cf         # Find file with fzf and open in VS Code
cgrep      # Search content and open at line in VS Code

# Modern terminal tools
z          # Smart directory jumping with zoxide
zi         # Interactive directory search with fzf
lg         # Visual git interface with lazygit
glow       # Markdown preview in terminal

# Enhanced FZF functions
gb         # Interactive git branch switcher
gl         # Interactive git log browser
rg         # Content search with ripgrep + fzf
fp         # Project finder

# Configuration switchers
tmux-config-switcher.sh minimal  # Use streamlined tmux
vim-minimal     # Fast vim config for quick edits
vim-full        # Full-featured vim config
vim-status      # Show current vim configuration

# Python development (pyenv + Poetry/pip)
pyset 3.11.9    # Set Python version for project (Poetry or pip)
vactivate       # Activate virtual environment (smart detection)
pyinfo          # Show Python environment info
pylist          # List installed and available Python versions
```

## 🐍 Python Development Workflow

The dotfiles include a streamlined Python workflow using **pyenv** (version management) that works seamlessly with both **Poetry** and **pip** projects:

### Quick Start

```bash
# 1. Install Python versions
pyenv install 3.11.9
pyenv install 3.12.4

# 2. Set a default Python version (enables python/python3 commands globally)
pyset --default 3.11.9

# Now python/python3 work everywhere using the default version
python --version
# Python 3.11.9

# Poetry project
cd my-poetry-project
pyset 3.11.9        # Set Python version + configure Poetry
poetry install      # Install dependencies
vactivate           # Activate venv

# pip project
cd my-pip-project
pyset 3.10.14       # Set Python version + create venv
vactivate           # Activate venv
pip install -r requirements.txt

# setuptools project (setup.py)
cd my-package
pyset 3.11.9        # Set Python version + create venv
vactivate           # Activate venv
pip install -e .    # Install in editable mode
```

### Benefits

- ✅ **Default version blocking** - `python`/`python3` blocked until you set a default (prevents accidental system Python usage)
- ✅ **Per-project Python versions** - Each project can use different Python versions via `.python-version`
- ✅ **Automatic detection** - `pyset` detects Poetry vs pip projects automatically
- ✅ **Smart precedence** - Project `.python-version` overrides global default automatically
- ✅ **Team consistency** - `.python-version` file ensures everyone uses same version
- ✅ **Works everywhere** - Integrates with Poetry, pip, setuptools, and VS Code

See `cheat` command for full list of Python helpers.

## 🎨 Theme System

### Quick Theme Switching

```bash
# Interactive theme switcher with preview
./bin/theme-switcher

# Direct theme switch
./bin/theme-switcher nord
./bin/theme-switcher tokyo-night
./bin/theme-switcher kanagawa
./bin/theme-switcher gruvbox-material
./bin/theme-switcher catppuccin-mocha
```

**Available Themes:**
- **Nord**: Cool, arctic-inspired professional theme
- **Tokyo Night**: Modern theme with vibrant city-light colors
- **Kanagawa**: Japanese-inspired earthy tones
- **Gruvbox Material**: Warm, retro colors with softer contrast
- **Catppuccin Mocha**: Soothing pastel colors

Themes apply consistently across neovim, tmux, shell prompts, and FZF. See [Theme Documentation](docs/theme-system.md) for details.

## 💻 VS Code Integration

### Setup

```bash
# Install VS Code settings and extensions
./install/install-vscode.sh
```

This installs:
- **Hybrid Vim mode**: VS Code shortcuts preserved, vim motions for text editing
- **Optimized settings**: Font ligatures, smooth scrolling, visual enhancements
- **Essential extensions**: Vim, GitLens, themes matching your dotfiles
- **Custom keybindings**: Vim-style window navigation, quick file access

### Key Features

- **Best of both worlds**: Use mouse/GUI when visual, vim motions for efficiency
- **Preserved VS Code shortcuts**: Ctrl+P, Ctrl+Shift+P, Ctrl+S all work normally
- **Quick terminal access**: Integrated terminal with your zsh configuration
- **Theme consistency**: VS Code themes match your terminal theme

See `configs/vscode/` for settings and customization options.

## ⚡ Streamlined Configurations

### Performance-Optimized Options

This dotfiles system now includes streamlined alternatives optimized for VS Code workflows:

**Shell**: 
- **Starship** prompt (200ms faster startup than Oh My Zsh)
- Modern zsh config without framework overhead
- No configuration switching needed - optimized by default

**Terminal Multiplexer**:
- Minimal tmux without plugins
- ESDF/WASD navigation toggle via `TMUX_NAV_STYLE`
- Switch with: `tmux-config-switcher.sh minimal`

**Editor**:
- Minimal vim with 5 essential plugins (<50ms startup)
- Full vim with 18+ plugins for extended sessions
- Switch with: `vim-minimal` or `vim-full`

These configurations follow the principle: **Use VS Code for development, terminal tools for quick edits**.

## 🎨 Customization

### Adding New Packages

**Base packages:** Edit `base_packages` array in `lib/packages.sh`
**Work packages:** Add to functions in `install_work_packages()`
**Personal packages:** Add to `personal_packages` array

### Adding New Configurations

1. Create config file in `configs/` (no leading dot)
2. Add mapping to `config_mappings` array in `setup.sh`
3. System automatically symlinks to hidden destination

### Adding Aliases/Functions

- **Aliases:** Add `.sh` file to `shell/aliases/`
- **Functions:** Add functions to `shell/functions.sh`
- Files are automatically sourced on shell startup

## 🔒 Security Features

- **HTTPS-only** downloads for all external resources
- **Checksum verification** for security-critical downloads
- **Safe operations** with `safe_sudo` wrapper showing commands
- **Automatic backups** before any file modifications
- **Input validation** for user-provided data

## 📚 Documentation

- **Theme System:** See `docs/theme-system.md` for detailed theme documentation
- **Quick Start:** See `docs/THEME_QUICK_START.md` for theme quick reference
- **AI Integration:** See `ai/` directory for Claude Code prompts and tools
- **Architecture:** Simple 2-file library design, human-readable codebase
- **Aliases:** See `shell/aliases/` for available shortcuts

## 🎯 Design Principles

1. **Ubuntu Only** - No cross-platform complexity
2. **Human Readable** - Any developer can understand the entire system in 20 minutes
3. **Essential Tools** - Focus on what developers actually need
4. **Visible Configs** - No hunting for hidden files
5. **Fail Safe** - Automatic backups and validation

## 🚨 Breaking Changes from v1

This is a complete rewrite that removes:
- Cross-platform support (dnf, pacman)
- VS Code installation (users manage their own editors)
- Complex Microsoft integration
- 8-module architecture

**Migration:** The system will automatically backup existing configs and install the simplified version.

## 📈 Stats

- **70% code reduction** from original complex system
- **Ubuntu-focused** for simplified maintenance
- **Human-readable** architecture
- **Essential functionality** preserved
- **Modern development tools** included

---

*A streamlined dotfiles system that gets out of your way and lets you focus on what matters: coding.*