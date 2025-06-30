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

1. **install.sh** (75 lines) - Main orchestrator that:
   - Loads modular core components
   - Coordinates installation workflow
   - Handles template processing

2. **scripts/core/** - Core framework modules:
   - `common.sh` - Shared utilities (is_wsl, get_windows_username, safe_sudo)
   - `cli.sh` - Command-line argument parsing
   - `environment.sh` - OS/WSL/package manager detection
   - `packages.sh` - Unified cross-distribution package management
   - `files.sh` - Backup and symlink operations (includes git config template processing)
   - `validation.sh` - Essential pre/post installation validation (117 lines, optimized)
   - `orchestration.sh` - Installation workflow management (includes setup_ssh, setup_wsl)
   - `logging.sh` - Consistent output formatting (30 lines, simplified)

3. **setup/** - Package installation modules:
   - `base_setup.sh` - Essential tools everyone needs
   - `work_setup.sh` - Professional development tools
   - `personal_setup.sh` - Personal preferences
   - `ai_setup.sh` - AI tools (Claude Code and prompts)

4. **scripts/** - Runtime enhancements:
   - `aliases/` - Command shortcuts (auto-sourced)
   - `functions/` - Utility functions (auto-sourced)
   - `security/` - Security utilities (core.sh, ssh.sh)
   - `wsl/` - Windows Subsystem for Linux integration

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

- `safe_sudo()` - Secure sudo wrapper with transparency
- `log()`, `success()`, `warn()`, `error()` - Colored logging
- `install_packages()` - Unified package installation
- `create_symlinks()` - Configuration file management
- `import_windows_ssh_keys()` - WSL SSH key import

## Development Guidelines

1. **Error handling**: Scripts use `set -e` for fail-fast behavior. Handle errors explicitly where needed.

2. **Adding new features**:
   - Package installations go in `setup/` scripts
   - Shell functions go in `scripts/functions/` (WSL-specific functions go in `scripts/aliases/wsl.sh`)
   - Aliases go in `scripts/aliases/`
   - Configuration templates go in `configs/`

3. **Testing**: No formal test suite exists. Test manually in clean environments before changes.

4. **Module dependencies**: Load order matters - common.sh must be loaded first, then logging.sh, before other modules.

4. **Logging**: Use provided logging functions for consistent output formatting.

5. **Python tools**: Work setup includes Python formatters (black, flake8, mypy, pylint) installed via pip3.

6. **Package verification**: After installation, verify critical commands exist to catch package name differences.

## AI Tools Installation

The dotfiles include an optional AI setup that installs:
1. **Claude Code** - Terminal-based AI coding assistant
2. **Custom AI prompts** - Curated prompts for enhanced AI interactions

### Installation
```bash
./install.sh --ai  # Install just AI tools
./install.sh --work --personal --ai  # Complete setup with AI
```

### Post-Installation
After installation:
1. Authenticate Claude Code:
   - Option 1: `claude --auth` (interactive)
   - Option 2: `export ANTHROPIC_API_KEY=your_key`
2. Access prompts: `~/.claude/`
3. Start coding: `claude` in any project directory

## Common Tasks

### Adding a new tool
1. Determine which setup script it belongs in (base/work/personal/ai)
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