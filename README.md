# Dotfiles

Modern Linux development environment with automatic setup and cross-distribution support.

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

### Modern CLI Tools
- `ls` → `eza --icons` (colorized with Git status)
- `cat` → `bat` (syntax highlighting and line numbers)
- `find` → `fdfind` (faster, respects .gitignore)
- `grep` → `ripgrep` (much faster searching)

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
update                     # Update all packages
install package            # Install package
reload                     # Reload shell config

# Development
serve                      # Start Python HTTP server
myip                       # Get public IP address

# Git shortcuts  
gs                         # git status
ga                         # git add
gc                         # git commit
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
    │   ├── general.sh     # General aliases
    │   ├── wsl.sh         # WSL-specific aliases
    │   └── git.sh         # Git aliases
    ├── functions/          # Shell functions
    │   ├── help-tmux.sh   # tmux help function
    │   └── wsl.sh         # WSL utility functions
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

## Safety Features

### Backup Protection
- Automatically backs up existing dotfiles to `~/dotfiles-backup-TIMESTAMP`
- Creates symlinks instead of overwriting files
- Easy rollback by removing symlinks

### Error Handling
- Stops installation on critical failures
- Continues with warnings for optional components
- Clear error messages with context

### Non-Destructive
- Never overwrites existing configurations
- Uses symlinks for easy management
- Preserves original files in backup directory

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
