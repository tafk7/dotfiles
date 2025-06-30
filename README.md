# Dotfiles

Modern Linux development environment with automatic setup and cross-distribution support.

## Key Features

- **🚀 Modular Architecture** - Clean separation of concerns with focused modules
- **🔒 Security-First** - HTTPS-only downloads, checksum verification, safe operations
- **🌍 Cross-Platform** - Works on Ubuntu/Debian, Fedora/RHEL, Arch Linux, and WSL
- **✅ Validation System** - Pre/post installation checks ensure everything works
- **📦 Smart Package Management** - Unified system across all distributions
- **🔄 Non-Destructive** - Automatic backups before any changes
- **📝 Template Support** - Dynamic configuration (e.g., Git user setup)

## Quick Start

```bash
# Base installation (essential tools, Docker, modern CLI tools, development basics)
./install.sh

# Add work tools (VS Code, Azure CLI, Node.js/Python dev tools)
./install.sh --work

# Add personal tools (media applications)
./install.sh --personal

# Add AI tools (Claude Code and prompts)
./install.sh --ai

# Everything
./install.sh --work --personal --ai

# Force mode for existing installations
./install.sh --force          # Backup and replace existing files
```

## What You Get

### Base Installation (Always)

The base installation includes essential tools needed by all users. For the exact package list, see `setup/base_setup.sh`.

Key categories include:
- **Essential tools**: Core utilities for development and system management
- **Modern CLI tools**: Enhanced replacements for common commands (ls, cat, find, grep)
- **Development basics**: Docker, Node.js, Python package management
- **System utilities**: Networking, fonts, SSH client
- **WSL integration**: Automatic detection and configuration for Windows Subsystem for Linux

### Work Setup (`--work`)

Professional development tools. See `setup/work_setup.sh` for the complete list.

### Personal Setup (`--personal`)

Personal utilities and media tools. See `setup/personal_setup.sh` for details.

### AI Setup (`--ai`)

AI development tools including Claude Code terminal assistant. See `setup/ai_setup.sh` for details.

## WSL Features

When running in WSL, automatically configures:

### SSH Key Management
```bash
# SSH keys automatically imported from Windows during install
win-ssh                    # List Windows SSH directory
sync-ssh                   # Re-sync SSH keys from Windows
```

### Windows Integration
```bash
# Clipboard
pbcopy                     # Copy to Windows clipboard
pbpaste                    # Paste from Windows clipboard
# File operations
winopen                    # Open file/directory in Windows
wpath                      # Convert WSL path to Windows path
lpath                      # Convert Windows path to WSL path

# Windows apps
explorer                   # Windows Explorer
```

### Directory Navigation
```bash
# Windows directories
win-ssh                    # List Windows SSH keys
```

## Shell Features

### Automatic Shell Integration
The installation automatically configures your shell (.bashrc or .zshrc) to:
- Source all custom aliases from `scripts/aliases/`
- Source all functions from `scripts/functions/`
- Enhance your shell with modern aliases and functions
- Preserve existing shell configuration

### Shell Enhancements

The installation configures modern CLI tools with safe aliases that preserve original commands:
- Enhanced `ls` with icons and Git status (via eza)
- Syntax highlighting for file viewing (via bat)  
- Fast file searching that respects .gitignore (via fd)
- Much faster grep searching (via ripgrep)

For a complete reference of all aliases and shortcuts, see [docs/aliases.md](docs/aliases.md).

## File Structure

```
dotfiles/
├── install.sh              # Main orchestrator
├── README.md               # This file
├── CLAUDE.md               # AI assistant guidance
├── setup/                  # Modular setup scripts
│   ├── base_setup.sh      # Core packages for everyone
│   ├── work_setup.sh      # Work-specific tools
│   └── personal_setup.sh  # Personal tools (minimal)
├── docs/                   # Documentation
│   ├── aliases.md         # Complete alias reference
│   ├── architecture.md    # System design and architecture
│   ├── customization.md   # How to extend the system
│   └── security.md        # Security troubleshooting
├── configs/                # Configuration files
│   ├── .editorconfig      # Cross-editor formatting rules
│   ├── .gitconfig         # Git configuration (with template support)
│   └── vscode/
│       └── settings.jsonc # VS Code settings (with comments)
└── scripts/
    ├── aliases/            # Shell aliases
    │   ├── general.sh     # General aliases (safe versions)
    │   ├── wsl.sh         # WSL-specific aliases
    │   ├── git.sh         # Git aliases
    │   └── docker.sh      # Docker aliases
    ├── functions/          # Shell functions
    │   └── help-tmux.sh   # tmux help function
    ├── core/               # Core framework modules
    │   ├── common.sh      # Shared utilities (is_wsl, get_windows_username)
    │   ├── cli.sh         # Argument parsing
    │   ├── environment.sh # Environment detection
    │   ├── files.sh       # File operations
    │   ├── logging.sh     # Logging functions
    │   ├── orchestration.sh # Workflow management
    │   ├── packages.sh    # Package management
    │   └── validation.sh  # Configuration validation
    ├── install/            # Installation helpers
    │   └── microsoft.sh   # Microsoft repository setup
    ├── security/           # Security utilities
    │   ├── core.sh        # Security functions
    │   └── ssh.sh         # SSH key management
    └── wsl/               # WSL integration
        └── core.sh        # WSL core functions
```

## Supported Systems

### Linux Distributions
- **Ubuntu/Debian** (uses apt)
- **Fedora/RHEL/CentOS** (uses dnf)
- **Arch/Manjaro** (uses pacman)

### Environments
- **Native Linux** - Full feature set
- **WSL 1/2** - Includes Windows integration features

## Security

The dotfiles system implements comprehensive security measures throughout installation and operation. For detailed security architecture and features, see [docs/architecture.md](docs/architecture.md#security-components). For security-related troubleshooting, see [docs/security.md](docs/security.md).

## Safety Features

### Backup Protection
- Automatically backs up existing dotfiles to `~/dotfiles-backup-TIMESTAMP`
- Creates symlinks instead of overwriting files
- Easy rollback by removing symlinks

### Error Handling
- Stops installation on critical failures
- Continues with warnings for optional components
- Clear error messages with context
- Comprehensive troubleshooting guide included

### Non-Destructive
- Never overwrites existing configurations without confirmation
- Uses symlinks for easy management
- Preserves original files in backup directory
- Multiple safety modes (interactive/force/skip)

## Troubleshooting

### Common Issues

**Installation fails with "checksum verification failed":**
```bash
# Clear cache and retry
rm -rf /tmp/dotfiles-*
./install.sh --force
```

**"Package not found" errors:**
```bash
# Update package lists
sudo apt update  # or dnf update / pacman -Sy
./install.sh --skip-existing
```

**Permission denied errors:**
```bash
# Refresh sudo permissions
sudo -v
./install.sh
```

**WSL SSH import issues:**
```bash
# Check Windows SSH directory
ls /mnt/c/Users/$(whoami)/.ssh/
# Manual sync if needed
sync-ssh
```

For comprehensive troubleshooting, see [docs/security.md](docs/security.md).

## Customization

See [docs/customization.md](docs/customization.md) for detailed instructions on:
- Adding standard packages
- Installing complex software
- Expanding personal setup
- Using framework functions

## Next Steps After Installation

1. **Restart your terminal** or run `source ~/.zshrc`
2. **Set up SSH keys** (WSL: already imported; Linux: `ssh-keygen -t ed25519`)

### WSL Users
- Use `win-ssh` to see imported Windows SSH keys
- Use `pbcopy` and `pbpaste` for clipboard integration

### AI Users
- Authenticate Claude Code: `claude --auth`
- View AI prompts: `ls ~/.claude/`
- Start Claude Code in your project: `claude`

### Development Setup Complete
- Docker is installed and user added to docker group
- Modern CLI tools replace standard commands
- Shell configured with plugins and modern prompt
- Ready for development with consistent environment across machines
