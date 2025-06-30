# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dotfiles management system for Linux environments (including WSL). It provides automated setup of a modern development environment across multiple Linux distributions.

## Key Commands

### Installation Commands
```bash
# Basic installation (core tools only)
./install.sh

# Full work environment setup
./install.sh --work

# Personal utilities setup  
./install.sh --personal

# Complete setup
./install.sh --work --personal
```

### Development Workflow

When modifying this codebase:

1. **Adding new packages**: Edit the appropriate setup script in `setup/`:
   - `base_setup.sh` - Essential tools everyone needs
   - `work_setup.sh` - Professional development tools
   - `personal_setup.sh` - Personal preferences

2. **Package mapping format**: `"generic:apt:dnf:pacman"`
   Example: `"exa:eza:exa:exa"` maps to the correct package name per distro

3. **Testing changes**: Always test in a clean environment before committing

## Architecture

### Core Components

1. **install.sh** - Main installer framework that:
   - Detects Linux distribution (Ubuntu/Debian, Fedora/RHEL, Arch)
   - Detects WSL environment
   - Backs up existing dotfiles
   - Orchestrates modular setup scripts

2. **setup/** - Modular installation scripts:
   - Each handles specific package categories
   - Uses unified package management functions
   - Supports apt, dnf, pacman, snap, npm

3. **scripts/** - Shell enhancements:
   - `aliases/` - Command shortcuts (auto-sourced)
   - `functions/` - Utility functions (auto-sourced)
   - `bin/` - Executable scripts (added to PATH)

### Key Design Patterns

1. **Cross-distribution package management**:
   ```bash
   declare -a package_mappings=(
     "build-essential:build-essential:make gcc:base-devel"
     "exa:eza:exa:exa"
   )
   build_package_list package_mappings packages "$pm"
   install_packages packages "description"
   ```

2. **Non-destructive installation**:
   - Uses symlinks instead of copying files
   - Backs up existing dotfiles to `~/.dotfiles_backup_TIMESTAMP`
   - Easy rollback by removing symlinks

3. **WSL integration**:
   - Auto-imports SSH keys from Windows
   - Clipboard integration (pbcopy/pbpaste)
   - Path conversion utilities

### Important Functions

- `handle_error()` - Consistent error reporting
- `log()`, `success()`, `warn()`, `error()` - Colored logging
- `install_packages()` - Unified package installation
- `create_symlinks()` - Configuration file management
- `copy-windows-ssh()` - WSL SSH key import

## Development Guidelines

1. **Error handling**: Scripts use `set -e` for fail-fast behavior. Handle errors explicitly where needed.

2. **Adding new features**:
   - Package installations go in `setup/` scripts
   - Shell functions go in `scripts/functions/` (WSL-specific functions go in `scripts/aliases/wsl.sh`)
   - Aliases go in `scripts/aliases/`
   - Configuration templates go in `configs/`

3. **Testing**: No formal test suite exists. Test manually in clean environments before changes.

4. **Logging**: Use provided logging functions for consistent output formatting.

5. **Python tools**: Work setup includes Python formatters (black, flake8, mypy, pylint) installed via pip3.

6. **Package verification**: After installation, verify critical commands exist to catch package name differences.

## Common Tasks

### Adding a new tool
1. Determine which setup script it belongs in (base/work/personal)
2. Add package mapping: `"tool:apt-name:dnf-name:pacman-name"`
3. Test installation on target distributions

### Adding shell customization
1. Create new file in `scripts/aliases/` or `scripts/functions/`
2. It will be automatically sourced on shell startup
3. Run `reload` alias to test without restarting shell

### Debugging installation issues
1. Check package manager detection in `install.sh`
2. Verify package name mappings are correct
3. Look for error messages in red (ERROR) output
4. WSL-specific issues show in purple (WSL) messages