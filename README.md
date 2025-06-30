# Dotfiles

Modern Linux development environment with automatic setup, cross-distribution support, and enterprise security features.

## Quick Start

```bash
# Base installation (shell, Docker, modern CLI tools)
./install.sh

# Add work tools (VS Code, Azure CLI, development packages)
./install.sh --work

# Add personal tools (currently just ffmpeg)
./install.sh --personal

# Everything
./install.sh --work --personal

# Safe modes for existing installations
./install.sh --skip-existing   # Skip all existing configurations
./install.sh --force          # Backup and replace existing files
```

## What You Get

### Base Installation (Always)
- **Zsh shell** with Oh My Zsh, plugins, and Powerlevel10k theme
- **Modern CLI tools**: `eza` (better ls), `bat` (better cat), `fzf` (fuzzy finder), `ripgrep` (better grep)
- **Development essentials**: Docker, Node.js, Python, Git, build tools
- **tmux** with custom key bindings and configuration
- **Powerline fonts** for proper terminal display
- **WSL integration** (automatically detected and configured)

### Work Setup (`--work`)
- **VS Code** with development extensions
- **Azure CLI** for cloud development
- **NPM packages**: yarn, TypeScript, ESLint, Prettier, nodemon

### Personal Setup (`--personal`)
- **ffmpeg** for media processing
- Ready for expansion (see [CUSTOMIZATION.md](CUSTOMIZATION.md))

## WSL Features

When running in WSL, automatically configures:

### SSH Key Management
```bash
# Keys imported from Windows during install
list-win-keys              # See available Windows SSH keys
use-key id_rsa_work        # Switch to specific key
sync-windows-ssh           # Re-sync from Windows
```

### Windows Integration
```bash
# Clipboard
pbcopy                     # Copy to Windows clipboard
pbpaste                    # Paste from Windows clipboard
ssh-copy                   # Copy SSH public key to clipboard

# File operations  
open-here                  # Open current directory in Windows Explorer
win-path                   # Convert WSL path to Windows path
wsl-path "C:\\path"        # Convert Windows path to WSL path

# Windows apps
explorer                   # Windows Explorer
code-win                   # Windows VS Code
```

### Directory Navigation
```bash
# Windows drives
cdrive                     # cd /mnt/c
ddrive                     # cd /mnt/d

# Windows directories
win-ssh                    # List Windows SSH keys
win-home                   # Go to Windows user directory
```

## Shell Features

### Modern CLI Tools (Safe Aliases)
- `ls` → `eza --icons` (colorized with Git status)
- `c` / `view` → `bat` (syntax highlighting and line numbers) 
- `f` → `fd` (faster find, respects .gitignore)
- `grep` → `ripgrep` (much faster searching)

> **Note:** Safe aliases preserve original commands for system compatibility. Use `\cat`, `\find`, etc. for original commands.

### tmux Shortcuts
```bash
help-tmux                  # Show tmux cheat sheet

# Sessions
tm session_name            # Create new session
ta session_name            # Attach to session  
tl                         # List sessions

# Key bindings (Ctrl-a prefix)
Ctrl-a |                   # Split horizontally
Ctrl-a -                   # Split vertically
Alt-Arrow                  # Switch panes (no prefix needed)
```

### Useful Aliases
```bash
# System
reload                     # Reload shell config
psg chrome                 # Find processes by name
myip                       # Get public IP address

# Development  
gs                         # git status
ga                         # git add
gc                         # git commit

# Archive operations (safe alternatives)
tarc archive.tar.gz files/ # Create compressed archive
tarx archive.tar           # Extract archive
untar archive.tar.gz       # Extract gzipped archive

# Process search with help
psg                        # Shows usage help
psg <name>                 # Find processes matching name
```

## File Structure

```
dotfiles/
├── install.sh              # Main installer with framework
├── README.md               # This file
├── setup/                  # Setup scripts
│   ├── base_setup.sh      # Core packages for everyone
│   ├── work_setup.sh      # Work-specific tools
│   ├── personal_setup.sh  # Personal tools (minimal)
│   └── CUSTOMIZATION.md   # How to add new software
├── configs/                # Configuration files
│   ├── .zshrc             # Shell configuration
│   ├── .tmux.conf         # tmux configuration
│   ├── .gitconfig         # Git configuration
│   ├── .vimrc             # Vim configuration
│   └── vscode/
│       └── settings.json   # VS Code settings
└── scripts/
    ├── aliases/            # Shell aliases
    │   ├── general.sh     # General aliases (safe versions)
    │   ├── wsl.sh         # WSL-specific aliases
    │   ├── git.sh         # Git aliases
    │   └── docker.sh      # Docker aliases
    ├── functions/          # Shell functions
    │   ├── help-tmux.sh   # tmux help function
    │   └── wsl.sh         # WSL utility functions
    ├── security/           # Security utilities
    │   ├── core.sh        # Security functions
    │   └── templates.sh   # Configuration templates
    └── bin/               # Executable scripts
```

## Supported Systems

### Linux Distributions
- **Ubuntu/Debian** (uses apt)
- **Fedora/RHEL/CentOS** (uses dnf)  
- **Arch/Manjaro** (uses pacman)

### Environments
- **Native Linux** - Full feature set
- **WSL 1/2** - Includes Windows integration features

## Security Features

### Download Security
- **SHA256 verification** for all downloaded files
- **HTTPS-only** policy for external downloads  
- **Network retry logic** with exponential backoff
- **Download validation** before execution

### Input Protection
- **Package name validation** to prevent injection attacks
- **Path traversal protection** for file operations
- **User input sanitization** across all interactive operations
- **Command validation** before execution

### SSH Security
- **Individual key validation** before import
- **Secure permission management** (600/644) automatically applied
- **Backup creation** before SSH modifications
- **Key format verification** using ssh-keygen

### Installation Safety
- **Interactive confirmation** for privilege escalation
- **Timestamped backups** of existing configurations
- **Safe symlink creation** with conflict resolution
- **Configuration validation** before activation

### System Protection
- **Safe aliases** that don't override critical system commands
- **Original command access** via `\command` or `command command`
- **Error trapping** with cleanup on failures
- **Strict mode** (`set -e`, `set -u`, `set -o pipefail`) in setup scripts

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
sync-windows-ssh
```

For comprehensive troubleshooting, see [SECURITY_TROUBLESHOOTING.md](SECURITY_TROUBLESHOOTING.md).

### Getting Help

- **Alias reference**: See [scripts/aliases/ALIAS_CHEATSHEET.md](scripts/aliases/ALIAS_CHEATSHEET.md)
- **Security issues**: See [SECURITY_TROUBLESHOOTING.md](SECURITY_TROUBLESHOOTING.md)  
- **tmux help**: Run `help-tmux` after installation

## Customization

See [setup/CUSTOMIZATION.md](setup/CUSTOMIZATION.md) for detailed instructions on:
- Adding standard packages
- Installing complex software
- Expanding personal setup
- Using framework functions

## Next Steps After Installation

1. **Restart your terminal** or run `source ~/.zshrc`
2. **Configure Powerlevel10k**: Run `p10k configure`
3. **Set up SSH keys** (WSL: already imported; Linux: `ssh-keygen -t ed25519`)
4. **Log out and back in** if shell was changed to zsh

### WSL Users
- Use `win-ssh` to see imported Windows SSH keys
- Try `open-here` to open current directory in Windows Explorer
- Use `pbcopy` and `pbpaste` for clipboard integration

### Development Setup Complete
- Docker is installed and user added to docker group
- Modern CLI tools replace standard commands
- Shell configured with plugins and modern prompt
- Ready for development with consistent environment across machines
