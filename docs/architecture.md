# Dotfiles Architecture

## Overview

This dotfiles system is designed as a modular, cross-platform Linux configuration management framework. It emphasizes security, maintainability, and ease of use while supporting multiple Linux distributions and WSL environments.

## Design Principles

1. **Modularity** - Each component has a single, well-defined responsibility
2. **Non-destructive** - Always backs up existing configurations before changes
3. **Cross-platform** - Works across Ubuntu/Debian, Fedora/RHEL, and Arch Linux
4. **Security-first** - HTTPS only, checksum verification, safe operations
5. **User-friendly** - Clear feedback, interactive prompts, comprehensive documentation

## System Architecture

```
┌─────────────────┐
│   install.sh    │  ← Entry point & orchestrator
└────────┬────────┘
         │
         ├─── Core Modules ──────────────────────┐
         │                                       │
    ┌────▼─────┐  ┌──────────┐  ┌──────────┐   │
    │ common   │  │ logging  │  │ environ  │   │
    └──────────┘  └──────────┘  └──────────┘   │
                                                │
    ┌──────────┐                                │
    │   cli    │                                │
    └──────────┘                                │
                                                │
    ┌──────────┐  ┌──────────┐  ┌──────────┐   │
    │ packages │  │  files   │  │validation│   │
    └──────────┘  └──────────┘  └──────────┘   │
                                                │
    ┌────────────────────────────────────────┐  │
    │           orchestration                │◄─┘
    └────────────────────────────────────────┘
                       │
         ┌─────────────┼─────────────────────┐
         │             │             │         │
    ┌────▼────┐  ┌────▼────┐  ┌────▼────┐  ┌────▼────┐
    │  base   │  │  work   │  │personal │  │   ai    │
    │ setup   │  │ setup   │  │ setup   │  │ setup   │
    └─────────┘  └─────────┘  └─────────┘  └─────────┘
```

## Core Modules

### 1. **scripts/core/common.sh**
Shared utilities used across modules:
- `is_wsl()` - Check if running in WSL environment
- `get_windows_username()` - Get Windows username in WSL

### 2. **scripts/core/logging.sh**
Provides unified logging functions with color-coded output:
- `log()` - General information (blue)
- `error()` - Error messages (red)
- `warn()` - Warnings (yellow)
- `success()` - Success messages (green)
- `wsl_log()` - WSL-specific messages (purple)
- `work_log()` - Work setup messages (cyan)
- `log_action()` - Track actions to state file

### 3. **scripts/core/environment.sh**
Detects and configures the runtime environment:
- OS validation (Linux only)
- WSL detection and version
- Package manager detection (apt/dnf/pacman)
- Environment variable setup

### 4. **scripts/core/cli.sh**
Handles command-line argument parsing:
- `--work` - Install professional development tools
- `--personal` - Install personal preferences
- `--ai` - Install AI development tools (Claude Code)
- `--force` - Force overwrite existing configs
- `--help` - Show usage information

### 5. **scripts/core/packages.sh**
Unified package management across distributions:
- Package name mapping system
- Distribution-specific installation commands
- Support for apt, dnf, pacman, snap, npm, pip
- Retry logic for network operations

### 6. **scripts/core/files.sh**
File operations and configuration management:
- Backup creation with timestamps
- Safe symlink creation with conflict resolution
- Configuration file deployment
- Template processing (Git config)
- Vim and zsh configuration handling
- VS Code settings deployment

### 7. **scripts/core/validation.sh**
Configuration and system validation:
- Pre-installation checks (commands, disk space, bash version)
- Shell script syntax validation
- JSON/JSONC validation
- Git config validation
- Symlink integrity checking
- Post-installation verification

### 8. **scripts/core/orchestration.sh**
Workflow coordination and phase management:
1. Pre-installation validation
2. System update and backup
3. Base package installation
4. Optional work/personal/ai packages
5. Configuration deployment
6. Shell integration setup
7. SSH setup (via setup_ssh())
8. WSL setup (via setup_wsl())
9. Post-installation validation

## Module Dependencies

The core modules must be loaded in a specific order due to dependencies:

1. **common.sh** - No dependencies (loaded first)
2. **logging.sh** - Depends on color definitions only
3. **environment.sh** - Depends on common.sh (is_wsl) and logging.sh
4. **cli.sh** - Depends on logging.sh
5. **packages.sh** - Depends on logging.sh and security/core.sh (safe_sudo)
6. **files.sh** - Depends on common.sh, logging.sh, and environment variables
7. **validation.sh** - Depends on logging.sh
8. **orchestration.sh** - Depends on all above modules

## Security Components

The dotfiles system implements defense-in-depth security across all operations.

### Core Security Module (`scripts/security/core.sh`)

Essential security functions:
- `safe_sudo()` - Transparent sudo operations with proper error handling
- `verify_download()` - SHA256 checksum verification for all external downloads
- `sanitize_input()` - Input validation to prevent injection attacks
- `retry_network_operation()` - Resilient network operations with exponential backoff

### SSH Security Module (`scripts/security/ssh.sh`)

SSH key management with enhanced security:
- Individual key validation using ssh-keygen before any operations
- Atomic permission setting (600 for private keys, 644 for public)
- Secure key copying with automatic backup creation
- Windows SSH key import validation (WSL environments)
- SSH config syntax validation before deployment

### Security Features Throughout

**Download Security:**
- HTTPS-only policy enforced for all external resources
- SHA256 verification against known checksums
- Network retry logic with exponential backoff
- Download validation before execution

**Input Protection:**
- Package name validation for all package manager operations
- Path construction protected against directory traversal
- User input sanitization in interactive prompts
- Safe file operations with automatic backups

**Installation Safety:**
- Timestamped backups of all existing configurations
- Safe symlink creation with conflict detection
- Comprehensive error handling and rollback capability
- Non-destructive operations by default

**System Protection:**
- Safe aliases that preserve original command access
- No direct command overrides that could break system scripts
- Modular architecture prevents cascading failures

## Integration Modules

### **scripts/wsl/core.sh**
Windows Subsystem for Linux integration:
- Windows username detection
- Path conversion utilities
- Clipboard integration (pbcopy/pbpaste)
- Windows application aliases

### **scripts/install/microsoft.sh**
Microsoft tool installation:
- Azure CLI setup
- VS Code installation
- Repository management

## Setup Modules

### **setup/base_setup.sh**
Core packages installed for all users:
- Essential development tools (git, curl, vim, build tools)
- Modern CLI replacements (eza, bat, fd, ripgrep, fzf)
- Docker and container tools
- Node.js and Python package managers
- System utilities and fonts

### **setup/work_setup.sh**
Professional development environment:
- VS Code with curated extensions
- Azure CLI for cloud development
- Node.js toolchain (yarn, TypeScript, ESLint, Prettier)
- Python development tools (black, flake8, mypy, pylint)

### **setup/personal_setup.sh**
Personal utilities and preferences:
- Media tools and applications
- Additional CLI utilities

### **setup/ai_setup.sh**
AI development tools:
- Claude Code terminal assistant
- AI prompt library deployment
- Node.js 18+ validation for compatibility

## Package Management Strategy

The system uses a mapping approach for cross-distribution compatibility:

```
"generic:apt:dnf:pacman"
"eza:eza:eza:eza"
"fd:fd-find:fd-find:fd"
```

This allows a single package list to work across all supported distributions.

## Configuration Deployment

Configurations are deployed as symlinks from `configs/` to the user's home directory:
- Non-destructive installation
- Automatic backups of existing files
- Interactive conflict resolution
- Template processing for dynamic values

## Error Handling

The system implements multiple layers of error handling:
1. `set -e` for fail-fast behavior
2. Module validation on load
3. Function-level error checking
4. User-friendly error messages
5. Cleanup on failure

## Extension Points

The architecture is designed for easy extension:
1. Add packages to setup scripts
2. Create new aliases in `scripts/aliases/`
3. Add functions to `scripts/functions/`
4. Create new setup modules for specific use cases
5. Add configuration templates to `configs/`

## Performance Considerations

- Modular loading reduces parse time
- Parallel operations where possible
- Minimal external command usage
- Efficient package manager detection caching

## Future Enhancements

Potential areas for expansion:
1. Configuration drift detection
2. Automated testing framework
3. Remote deployment capabilities
4. Plugin system for third-party extensions
5. GUI configuration tool