# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a simplified, Ubuntu-focused dotfiles management system built around just 3 core files (~800 lines total). The architecture emphasizes simplicity, security, and maintainability while providing a comprehensive development environment setup.

## Common Commands

### Installation & Setup
```bash
# Base installation (essential tools + Docker)
./install.sh

# With professional development tools (Azure CLI, Node.js/Python tools)
./install.sh --work

# With personal media tools
./install.sh --personal

# Force replacement with automatic backups
./install.sh --force

# Full installation
./install.sh --work --personal --force
```

### Validation & Testing
```bash
# Validate installation
./scripts/validate-install.sh

# Validate with specific packages
./scripts/validate-install.sh --work --personal

# Verbose mode for debugging
./scripts/validate-install.sh --verbose

# Auto-fix mode
./scripts/validate-install.sh --fix

# Validate specific category
./scripts/validate-install.sh --category docker
```

### Development Workflow
```bash
# Reload shell configuration without restart
reload

# Theme management
./scripts/theme-switcher.sh          # Interactive theme selector
./scripts/theme-switcher.sh nord     # Set specific theme
themes                               # List available themes

# WSL-specific commands (when applicable)
sync-ssh                            # Import SSH keys from Windows
pbcopy / pbpaste                    # Cross-platform clipboard
```

## High-Level Architecture

### Core Structure
```
dotfiles/
├── install.sh           # Main orchestrator (243 lines)
├── lib/
│   ├── core.sh         # Core utilities & system ops (313 lines)
│   └── packages.sh     # Package management (288 lines)
├── configs/            # Visible config files (no dots!)
├── scripts/            # Runtime scripts & shell integration
├── ai/                 # AI-assisted development tools
└── docs/              # Documentation
```

### Key Design Principles
1. **3-file core** - Entire system in just install.sh + 2 library files
2. **Ubuntu-only** - Removed cross-platform complexity for cleaner code
3. **Visible configs** - All config files stored without dots for easy discovery
4. **Non-destructive** - Automatic timestamped backups before any changes
5. **Linear flow** - Simple, sequential installation process
6. **WSL-aware** - Automatic detection and integration for Windows Subsystem for Linux

### Configuration Mappings
All configurations in `configs/` are symlinked to their hidden destinations:
- `configs/bashrc` → `~/.bashrc`
- `configs/zshrc` → `~/.zshrc`
- `configs/init.vim` → `~/.config/nvim/init.vim`
- `configs/tmux.conf` → `~/.tmux.conf`
- `configs/gitconfig` → `~/.gitconfig` (template-processed)
- `configs/profile` → `~/.profile`
- `configs/ripgreprc` → `~/.ripgreprc`
- `configs/config/bat/` → `~/.config/bat/`
- `configs/config/fd/` → `~/.config/fd/`

### Package Categories
- **Base**: Always installed - git, neovim, tmux, eza, bat, fd, ripgrep, fzf, Docker
- **Work** (`--work`): Azure CLI, yarn, ESLint, Prettier, black, ruff
- **Personal** (`--personal`): ffmpeg, yt-dlp
- **WSL**: Automatically installed if WSL detected - socat, wslu

### AI Integration
The repository includes comprehensive AI-assisted development tools:
- **Slash commands** in `ai/commands/` for structured AI interactions
- **Global CLAUDE.md** at `ai/global-CLAUDE.md` with the Arete framework
- **Artifact workflow** for managing AI-generated content
- **Project templates** for repository-specific AI configuration

## Development Guidelines

### Adding New Packages
1. For base packages: Edit `base_packages` array in `lib/packages.sh`
2. For work packages: Add to `install_work_packages()` function
3. For personal packages: Add to `personal_packages` array

### Adding New Configurations
1. Create config file in `configs/` directory (no leading dot)
2. Add mapping to `config_mappings` array in `install.sh`
3. System automatically creates symlink during installation

### Modifying Shell Integration
- Add aliases in `scripts/aliases/` (auto-loaded)
- Add functions in `scripts/functions/` (auto-loaded)
- Environment variables go in `scripts/env/common.sh`

### Theme System
The repository includes 5 pre-configured themes (Nord, Tokyo Night, Kanagawa, Gruvbox Material, Catppuccin Mocha) with unified colors across neovim, tmux, shell, and FZF. Themes can be switched using the interactive theme-switcher.sh script.

## Important Notes

- This is an Ubuntu/WSL-only system - no macOS or other platform support
- Docker is always installed as part of base packages
- All operations are non-destructive with automatic backups
- Template processing is supported (currently only gitconfig)
- The system follows a security-first approach with HTTPS-only downloads and checksum verification