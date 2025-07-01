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

# AI tools (Claude Code and prompts)
./install.sh --ai

# Force overwrite existing configs
./install.sh --force

# Complete setup
./install.sh --work --personal --ai
```

### Runtime Commands (Available After Installation)
```bash
# Reload shell configuration without restarting
reload

# Import SSH keys from Windows (WSL only)
sync-ssh

# Search for running processes
psg <name>

# View markdown files with syntax highlighting  
md <file>
```

### Development Workflow

When modifying this codebase:

1. **Adding new packages**: Edit the appropriate setup script in `setup/`:
   - `base_setup.sh` - Essential tools everyone needs
   - `work_setup.sh` - Professional development tools
   - `personal_setup.sh` - Personal preferences

2. **Package mapping format**: `"generic:apt:dnf:pacman"`
   Example: `"exa:eza:exa:exa"` maps to the correct package name per distro
   Use `"SKIP"` for packages not available on a distribution

3. **Testing changes**: Always test in a clean environment before committing

## Installation Workflow

The system follows a strict 7-phase installation process:

1. **Pre-installation validation** - Checks git, curl, bash 4+, disk space (100MB minimum)
2. **System preparation** - Cleans broken repos, updates system, creates backup directory  
3. **Base setup** - Installs essential tools (always runs)
4. **Optional components** - Work/Personal/AI tools based on flags
5. **Configuration** - Creates symlinks, processes templates, sets up shell integration
6. **WSL-specific setup** - SSH key import, clipboard integration (if WSL detected)
7. **Post-installation validation** - Verifies critical installations and symlinks

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
     "build-essential:build-essential:make gcc gcc-c++ kernel-devel:base-devel"
     "eza:eza:eza:eza"
     "glow:SKIP:SKIP:glow"  # Use SKIP when package unavailable
   )
   build_package_list package_mappings packages "$pm"
   install_packages packages "description"
   ```

2. **Non-destructive installation**:
   - Uses symlinks instead of copying files
   - Backs up existing dotfiles to `~/dotfiles-backup-TIMESTAMP` (note: changed format)
   - Easy rollback by removing symlinks

3. **WSL integration**:
   - Auto-imports SSH keys from Windows using `sync-ssh`
   - Clipboard integration (pbcopy/pbpaste aliases)
   - Path conversion utilities and Windows username detection

4. **Error handling and safety**:
   - `safe_sudo()` shows commands before execution for transparency
   - Scripts use `set -e` for fail-fast behavior
   - Graceful degradation for optional features
   - Colored logging with specific message types

5. **Module loading dependencies**:
   - `common.sh` must be loaded first (provides core utilities)
   - `logging.sh` must be loaded second (provides colored output)
   - Other modules can be loaded in any order

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

5. **Logging**: Use provided logging functions for consistent output formatting:
   - `log()` (blue) - General information
   - `success()` (green) - Successful operations
   - `warn()` (yellow) - Warnings and fallbacks
   - `error()` (red) - Errors and failures  
   - `wsl_log()` (purple) - WSL-specific messages

6. **Python tools**: Handles PEP 668 restrictions with fallback chain:
   - Try `pipx` first (user-isolated environments)
   - Fall back to `pip --user` (user-space installation)
   - Last resort: `pip --break-system-packages`

7. **NPM configuration**: Sets up user-space global installations in `~/.npm-global` to avoid permission issues

8. **Package verification**: After installation, verify critical commands exist to catch package name differences.

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
1. Check package manager detection in `scripts/core/environment.sh`
2. Verify package name mappings are correct for target distribution
3. Look for error messages in red (ERROR) output
4. WSL-specific issues show in purple (WSL) messages
5. For Microsoft repository issues, check GPG key verification and checksums
6. Use `./install.sh --force` to overwrite existing configurations

## WSL-Specific Features

### SSH Key Management
- `sync-ssh` command imports SSH keys from Windows SSH agent
- Keys are copied with proper permissions (600 for private, 644 for public)
- Automatically detects Windows username for key import path

### Windows Integration
- Clipboard aliases: `pbcopy` and `pbpaste` for cross-platform compatibility
- Path conversion utilities for Windows/WSL interoperability
- Windows username detection for cross-system operations

### WSL Detection
Uses multiple methods to detect WSL environment:
- `/proc/sys/fs/binfmt_misc/WSLInterop` file existence
- `WSL_DISTRO_NAME` environment variable
- Graceful fallback for different WSL versions