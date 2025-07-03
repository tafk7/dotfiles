# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a streamlined dotfiles management system for Ubuntu environments (including WSL). It provides automated setup of a modern development environment with a focus on simplicity and maintainability.

**Key Characteristics:**
- Ubuntu-only support (no cross-platform complexity)
- Modular architecture with clear separation of concerns
- Visible config files in `configs/` directory (no hidden source files)
- Theme system with 5 pre-configured color schemes
- Docker and Azure CLI as essential professional tools

## Common Commands

### Installation
```bash
# Basic installation (essential tools + Docker)
./install.sh

# Work environment (includes Azure CLI, Node.js/Python dev tools)
./install.sh --work

# Personal utilities (media tools)
./install.sh --personal

# Force overwrite existing configs (creates backups)
./install.sh --force

# Complete setup
./install.sh --work --personal --force
```

### Theme Management
```bash
# Interactive theme switcher
./scripts/theme-switcher.sh

# Available themes: nord, tokyo-night, kanagawa, gruvbox-material, catppuccin
```

### Runtime Commands (After Installation)
```bash
reload          # Reload shell configuration without restarting
sync-ssh        # Import SSH keys from Windows (WSL only)
psg <name>      # Search for running processes
md <file>       # View markdown files with syntax highlighting
```

## Architecture

The codebase is organized into modular components:

1. **install.sh** - Main installer
   - Parses command-line arguments
   - Orchestrates installation workflow (7 steps)
   - Manages configuration file mappings

2. **lib/** - Core libraries
   - `core.sh`: Logging, WSL detection, file operations, validation
   - `packages.sh`: Package installation and management

3. **scripts/** - Runtime scripts
   - `env/`: Environment variables and settings
   - `aliases/`: Shell aliases organized by category
   - `functions/`: Shared shell functions
   - `theme-switcher.sh`: Interactive theme management

### Key Data Structures

**Configuration Mappings**:
```bash
config_mappings=(
    "$CONFIGS_DIR/bashrc:$HOME/.bashrc"
    "$CONFIGS_DIR/zshrc:$HOME/.zshrc"
    "$CONFIGS_DIR/init.vim:$HOME/.config/nvim/init.vim"
    # ... additional mappings
)
```

**Package Arrays**:
- `base_packages` array for essential tools
- `personal_packages` array for media tools
- Work packages installed via functions

## Development Workflow

### Adding New Packages
1. **Base packages**: Add to `base_packages` array in lib/packages.sh
2. **Work packages**: Add to `install_work_packages()` in lib/packages.sh
3. **Personal packages**: Add to `personal_packages` array in lib/packages.sh

### Adding New Configuration Files
1. Create visible config file in `configs/` (no leading dot)
2. Add mapping to `config_mappings` array in install.sh
3. System will automatically symlink during installation

### Adding New Themes
1. Create theme directory in `configs/themes/<theme-name>/`
2. Add theme files following existing pattern (neovim, tmux, shell configs)
3. Update theme-switcher.sh to include new theme

### Testing Changes
```bash
# Always use experimental branch
git checkout -b experimental

# Test full installation
./install.sh --work --personal --force

# Verify symlinks
ls -la ~/.* | grep " -> "

# Check Docker group
groups | grep docker
```

## Installation Process

The installer follows a 7-step workflow:

1. **Validation** - Prerequisites check (bash 4+, 10MB space, required commands)
2. **Package Installation** - Base packages + optional work/personal
3. **Shell Environment** - Oh My Zsh, Powerlevel10k, zsh plugins
4. **Configuration** - Create symlinks for all config files
5. **WSL Integration** - Clipboard and SSH setup (if WSL detected)
6. **Final Setup** - npm global directory configuration
7. **Final Validation** - Verify critical symlinks exist

## WSL-Specific Features

When WSL is detected (via is_wsl() in lib/core.sh:47):
- Installs socat and wslu packages
- Sets up pbcopy/pbpaste clipboard integration
- Configures SSH key import from Windows
- Detects Windows username for cross-system operations

## Error Handling

The system uses strict error handling:
- `set -e` in all scripts (fail on error)
- Validation before operations
- Automatic backups before overwrites
- Clear error messages with recovery suggestions

## Important Implementation Details

1. **Git Config Processing**: The gitconfig file is a template - installer prompts for user name/email
2. **Docker Group**: User is added to docker group automatically (requires re-login)
3. **Symlink Strategy**: All configs symlink from visible source to hidden destination
4. **Theme System**: Unified colors across neovim, tmux, shell prompt, and FZF
5. **Package Sources**: Uses official Ubuntu repos, Docker repo, and Microsoft repo for Azure CLI
6. **Environment Variables**: Centralized in `scripts/env/common.sh`, including WSL detection
7. **SSH Key Import**: WSL users can import SSH keys from Windows with `sync-ssh` command