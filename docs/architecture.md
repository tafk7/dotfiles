# Simplified Dotfiles Architecture

## Overview

This dotfiles system is designed as a streamlined, Ubuntu-focused configuration management framework. It emphasizes simplicity, maintainability, and essential functionality while removing unnecessary complexity.

## Design Principles

1. **Simplicity** - Just 3 focused files with clear responsibilities
2. **Non-destructive** - Always backs up existing configurations before changes  
3. **Ubuntu-focused** - Optimized for Ubuntu/WSL environments only
4. **Security-first** - HTTPS only, checksum verification, safe operations
5. **Human-readable** - Any developer can understand the entire system in 20 minutes
6. **Visible configs** - No hidden source files, easy to discover and edit

## System Architecture

```
┌─────────────────┐
│   install.sh    │  ← Entry point (243 lines)
└────────┬────────┘
         │
         ├─── Simplified Modules ────────┐
         │                               │
    ┌────▼─────┐          ┌─────────────▼┐
    │lib/      │          │configs/      │
    │core.sh   │          │(visible      │
    │(313      │          │ files)       │
    │ lines)   │          │              │
    └──────────┘          └──────────────┘
         │
    ┌────▼─────┐          ┌──────────────┐
    │lib/      │          │scripts/      │
    │packages  │          │aliases &     │
    │.sh       │          │functions     │
    │(288      │          │              │
    │ lines)   │          └──────────────┘
    └──────────┘
```

## Core Components

### 1. install.sh (238 lines)
**Main orchestrator and entry point**

```bash
├── Command line parsing (--work, --personal, --force, --help)
├── Help system and user guidance  
├── Configuration symlink creation
├── Shell integration setup
└── Installation workflow coordination
```

**Key Functions:**
- `parse_arguments()` - Handle CLI flags
- `show_help()` - Display usage information
- `create_config_symlinks()` - Link visible configs to hidden destinations
- `run_installation()` - Coordinate entire installation process

### 2. lib/core.sh (313 lines)
**Core utilities and system operations**

```bash
├── Logging system (colored output)
├── WSL detection and integration
├── Environment validation  
├── File operations (symlinks, backups)
├── SSH key management
└── Security functions
```

**Key Functions:**
- `log()`, `success()`, `warn()`, `error()` - Colored output functions
- `is_wsl()` - Detect Windows Subsystem for Linux
- `get_windows_username()` - Cross-platform user detection
- `safe_sudo()` - Transparent sudo operations
- `create_backup_dir()` - Timestamped backup creation
- `safe_symlink()` - Non-destructive symlink creation
- `setup_wsl_clipboard()` - pbcopy/pbpaste integration
- `import_windows_ssh_keys()` - SSH key synchronization
- `validate_prerequisites()` - Pre-installation checks
- `validate_installation()` - Post-installation verification

### 3. lib/packages.sh
**Package management and installation**

```bash
├── Ubuntu package installation
├── Docker setup (always installed)  
├── Azure CLI installation (work flag)
├── Node.js development tools
├── Python development tools
└── WSL-specific packages
```

**Key Functions:**
- `install_single_package()` - Individual package installation
- `install_packages()` - Bulk package installation
- `install_base_packages()` - Essential tools for everyone
- `install_docker()` - Container platform setup
- `install_work_packages()` - Professional development tools
- `install_azure_cli_ubuntu()` - Cloud development tools
- `install_nodejs_tools()` - JavaScript ecosystem
- `install_python_tools()` - Python development environment
- `install_personal_packages()` - Media and entertainment tools

### 4. scripts/
**Runtime scripts and shell configuration**

The scripts directory contains modular components loaded at shell startup:

```
scripts/
├── env/
│   └── common.sh          # Environment variables and settings
├── aliases/               # Shell aliases organized by category
│   ├── general.sh        # Common command aliases (ls, cd, etc.)
│   ├── docker.sh         # Docker shortcuts
│   ├── git.sh           # Git workflow aliases
│   └── wsl.sh           # WSL-specific integrations
├── functions/            # Reusable shell functions
│   ├── shared.sh        # Common utilities (mkcd, extract, etc.)
│   └── help-tmux.sh     # Tmux helper functions
└── theme-switcher.sh    # Interactive theme management
```

**Key Features:**
- **Environment Setup**: Centralized environment variables in `env/common.sh`
- **WSL Detection**: Automatic detection and configuration for WSL environments
- **Modular Loading**: Shell configs source these files dynamically
- **SSH Key Import**: `sync-ssh` command for WSL users to import Windows SSH keys

## Configuration Management

### Visible Configuration Files

All configuration files are stored visibly (no leading dots) for easy discovery and editing:

```
configs/
├── bashrc              → ~/.bashrc
├── zshrc               → ~/.zshrc  
├── init.vim            → ~/.config/nvim/init.vim
├── tmux.conf           → ~/.tmux.conf
├── gitconfig           → ~/.gitconfig (template processed)
├── editorconfig        → ~/.editorconfig
├── profile             → ~/.profile
├── ripgreprc           → ~/.ripgreprc
└── config/             → ~/.config/
    ├── bat/config      → ~/.config/bat/config
    └── fd/ignore       → ~/.config/fd/ignore
```

**Benefits:**
- Tab completion works when editing configs
- Easy to find and browse in file managers
- Clear file organization  
- Still symlinked to expected hidden locations

### Template Processing

The system supports dynamic configuration through templates:

- **gitconfig**: Prompts for user name and email, processes `{{GIT_NAME}}` and `{{GIT_EMAIL}}` placeholders
- **Future templates**: Easy to add new template variables

## Installation Workflow

The system follows a clean, linear workflow:

```
1. Prerequisites Validation
   ├── Check bash version (4.0+)
   ├── Verify required commands (curl, wget, git)
   ├── Check available disk space (100MB+)
   └── Detect Ubuntu version and WSL

2. Package Installation  
   ├── Update apt package lists
   ├── Install base packages (always)
   ├── Install Docker (always)
   ├── Install work packages (optional)
   ├── Install personal packages (optional)
   └── Install WSL packages (if applicable)

3. Configuration Setup
   ├── Create timestamped backup directory
   ├── Process git config template  
   ├── Create symlinks for all configs
   └── Setup shell integration

4. WSL Integration (if applicable)
   ├── Setup clipboard integration (pbcopy/pbpaste)
   ├── Import SSH keys from Windows
   └── Configure cross-platform utilities

5. Final Setup & Validation
   ├── Configure NPM global directory
   ├── Verify critical symlinks exist
   ├── Display success message and next steps
   └── Return success/failure status
```

## Package Categories

### Base Packages (Always Installed)
Essential tools for any Ubuntu development environment:

```bash
# Build and development essentials
build-essential, curl, wget, git, unzip, zip, jq

# Modern shell environment  
zsh, neovim

# Enhanced CLI tools
eza (with tree functionality), bat, fd-find, ripgrep, fzf

# Development platforms
python3-pip, pipx, nodejs, npm

# System utilities
net-tools, fontconfig, openssh-client

# Container platform
docker-ce, docker-compose (with user group setup)
```

### Work Packages (--work flag)
Professional development tools:

```bash
# Cloud development
azure-cli (Ubuntu-specific installation)

# Node.js ecosystem  
yarn, eslint, prettier

# Python development
black, ruff (via pipx for isolation)
```

### Personal Packages (--personal flag)
Media and entertainment tools:

```bash
# Media processing
ffmpeg, yt-dlp
```

### WSL Packages (Automatic if WSL detected)
Windows Subsystem for Linux integration:

```bash
# WSL utilities
socat, wslu
```

## Runtime Integration

### Shell Integration
The system integrates with shell environments through:

```
scripts/
├── aliases/            # Command shortcuts
│   ├── docker.sh      # Docker command aliases
│   ├── general.sh     # Modern CLI replacements  
│   ├── git.sh         # Git workflow shortcuts
│   └── wsl.sh         # WSL-specific commands
└── functions/          # Utility functions
    └── help-tmux.sh   # tmux helper functions
```

**Auto-loading**: All `.sh` files are automatically sourced on shell startup

### Available Commands

After installation, these commands become available:

```bash
# Shell management
reload              # Reload shell without restart

# Process management  
psg <name>          # Search running processes

# File operations
md <file>           # View markdown with syntax highlighting

# WSL integration (if applicable)
sync-ssh            # Import SSH keys from Windows
pbcopy / pbpaste    # Cross-platform clipboard
```

## Security Architecture

### Safe Operations
- **safe_sudo()**: Shows commands before execution for transparency
- **Automatic backups**: All existing configs backed up before changes
- **Input validation**: User-provided data is validated before use
- **Fail-fast**: Scripts exit immediately on any error

### Download Security
- **HTTPS-only**: All external downloads use secure connections
- **Checksum verification**: Security-critical downloads verified
- **Temporary files**: Proper cleanup of temporary files and directories

### Permission Management
- **SSH keys**: Proper permissions (600 for private, 644 for public)
- **Directories**: Secure permissions for sensitive directories
- **Docker group**: Safe addition to docker group for container access

## Extensibility

### Adding New Packages
1. **Base packages**: Edit `base_packages` array in `lib/packages.sh`
2. **Work packages**: Add to `install_work_packages()` function
3. **Personal packages**: Add to `personal_packages` array

### Adding New Configurations
1. Create config file in `configs/` (no leading dot)
2. Add mapping to `config_mappings` array in `install.sh`
3. System automatically creates symlink to hidden destination

### Adding Runtime Features
1. **Aliases**: Create `.sh` file in `scripts/aliases/`
2. **Functions**: Create `.sh` file in `scripts/functions/`  
3. Files are automatically sourced on shell startup

## Error Handling

### Validation Strategy
- **Pre-installation**: Check prerequisites before starting
- **During installation**: Validate each step before proceeding
- **Post-installation**: Verify critical components are working

### Recovery Mechanisms
- **Automatic backups**: Easy rollback if issues occur
- **Graceful degradation**: Optional features fail safely
- **Clear error messages**: Specific guidance when things go wrong

## Performance Characteristics

### Installation Speed
- **Streamlined process**: No complex orchestration overhead
- **Parallel operations**: Multiple packages installed efficiently
- **Minimal dependencies**: Only essential components included

### Resource Usage
- **Small footprint**: ~800 lines of code total
- **Efficient operations**: No redundant or duplicate processes
- **Clean dependencies**: Clear module relationships

---

## Comparison with Original Architecture

### Before: Complex 8-Module System
- 8 core modules with intricate dependencies
- Cross-platform package management complexity
- 264-line Microsoft integration
- 7-phase orchestrated installation
- 1,400+ lines of code

### After: Simple 3-File System  
- 3 focused files with clear responsibilities
- Ubuntu-only simplicity
- Integrated Azure CLI (30 lines)
- Linear installation process
- 800 lines of code

**Result**: 43% code reduction while maintaining all essential functionality and improving maintainability.