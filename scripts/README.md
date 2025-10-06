# Scripts Directory

Quick reference for the dotfiles scripts organization.

## 📁 Directory Structure

```
scripts/
├── aliases/              # Shell aliases by category (auto-loaded)
├── env/                  # Environment variables (auto-loaded)
├── functions/            # Shell functions (auto-loaded)
├── installers/           # Tool installation scripts
├── utils/                # Utility commands
└── *.sh                  # Main commands
```

## 🚀 Main Commands

### Daily Use
```bash
./scripts/check-setup.sh           # Validate dotfiles installation
./scripts/theme-switcher.sh        # Change color theme (interactive)
./scripts/update-configs.sh        # Refresh configuration files
./scripts/update-claude-commands.sh # Update AI slash commands
```

### Configuration Switchers
```bash
./scripts/tmux-config-switcher.sh minimal  # Streamlined tmux config
./scripts/vim-config-switcher.sh minimal   # Lightweight vim config
```

## 🔧 Installers (`installers/`)

Individual tool installers (called by `./install.sh`):
- `install-starship.sh` - Cross-shell prompt
- `install-eza.sh` - Modern ls replacement
- `install-lazygit.sh` - Terminal UI for git
- `install-zoxide.sh` - Smart directory jumper
- `install-nvm.sh` - Node Version Manager
- `install-vscode.sh` - VS Code settings and extensions

**Usage:**
```bash
./scripts/installers/install-starship.sh
```

## 🎨 Shell Integration

### Aliases (`aliases/`)
Auto-loaded command shortcuts organized by topic:
- `general.sh` - Common commands (ls, cd, etc.)
- `git.sh` - Git shortcuts
- `docker.sh` - Docker commands
- `node.sh` - Node.js/npm
- `python.sh` - Python development
- `vim.sh` - Vim/Neovim
- `vscode.sh` - VS Code
- `wsl.sh` - WSL-specific

### Functions (`functions/`)
Shared shell functions (auto-loaded):
- `core.sh` - Navigation, process management, archives
- `fzf-extras.sh` - Advanced FZF integrations (optional)
- `wsl.sh` - WSL utilities

### Environment (`env/`)
Environment variables (auto-loaded):
- `common.sh` - Editor, PATH, theme config
- `fzf.sh` - FZF configuration
- `wsl.sh` - WSL-specific environment

## 🛠️ Utilities (`utils/`)

Standalone utility commands:
- `cheatsheet.sh` - Display all keybindings (`cheat` command)
- `fr.sh` - Safe find/replace (`fr` command)

## 📝 Adding New Scripts

### Add Installer
1. Create `scripts/installers/install-<tool>.sh`
2. Follow pattern: check version, download, install to `/usr/local/bin`, verify
3. Add call to `install.sh` if part of base/work/personal packages

### Add Alias
1. Add to appropriate file in `scripts/aliases/`
2. Automatically sourced on shell startup

### Add Function
1. Add to appropriate file in `scripts/functions/`
2. Automatically sourced on shell startup

### Add Command
1. Create `scripts/<command-name>.sh`
2. Make executable: `chmod +x scripts/<command-name>.sh`
3. Document in this README

## 🔍 Script Conventions

- **Executable:** All scripts have `+x` permission
- **Shebang:** `#!/bin/bash` (Ubuntu-only, no POSIX requirement)
- **Error handling:** Use `set -euo pipefail` for safety
- **Logging:** Source `lib/core.sh` for consistent logging
- **Self-contained:** Installers can run independently
