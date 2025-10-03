# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Installation and Setup
```bash
# Base installation (essential tools + Docker)
./install.sh

# Add work tools (Azure CLI, Node.js/Python dev tools)
./install.sh --work

# Add personal tools (media applications)
./install.sh --personal

# Force mode for existing installations (backup and replace)
./install.sh --force

# Update configuration files after changes
./scripts/update-configs.sh

# Install VS Code integration
./scripts/install-vscode.sh

# Install Starship prompt
./scripts/install-starship.sh

# Switch configurations
./scripts/tmux-config-switcher.sh minimal  # Streamlined tmux
vim-minimal     # Fast vim for quick edits
vim-full        # Full-featured vim config
```

### Validation and Testing
```bash
# Check installation status (basic verification)
./scripts/check-setup.sh

# Planned future feature: validate-install.sh
# Will support: --work --personal --fix --category options
# Currently use check-setup.sh for basic validation
```

### Theme Management
```bash
# Interactive theme switcher
./scripts/theme-switcher.sh

# Direct theme switch
./scripts/theme-switcher.sh nord
./scripts/theme-switcher.sh tokyo-night
```

### Development Commands
```bash
# Find and replace utility
./scripts/utils/fr.sh

# Reload shell configuration
reload

# Search processes
psg <name>

# View markdown with syntax highlighting
md <file>
```

## Environment Variables

### Navigation Style
- `TMUX_NAV_STYLE=wasd` - Use WASD navigation in tmux (default is ESDF)
- Add to your `.zshrc.local` or `.bashrc.local` to persist

## Architecture

This is a simplified Ubuntu dotfiles system with a 2-file core architecture:

### Core Libraries
- **lib/core.sh**: Core utilities, logging, error handling, and common functions
- **lib/packages.sh**: Package definitions and installation functions

### Key Principles
1. **Ubuntu-only**: No cross-platform complexity, focused on Ubuntu/WSL
2. **Visible configs**: All configurations in `configs/` without leading dots
3. **Non-destructive**: Automatic backups before any changes
4. **Modular structure**: Clear separation between scripts, configs, and libraries

### Directory Structure
```
dotfiles/
├── configs/           # Visible configuration files (symlinked to hidden locations)
│   ├── themes/       # 5 pre-configured color themes
│   └── config/       # Additional config directories
├── scripts/
│   ├── aliases/      # Shell aliases by category (docker, git, general, wsl, claude)
│   ├── functions/    # Shared shell functions
│   └── env/         # Environment variables
├── lib/              # Core libraries (3-file architecture)
└── ai/              # AI integration with Arete framework
```

### Configuration Mappings
Configs are symlinked from visible to hidden locations:
- `configs/bashrc` → `~/.bashrc`
- `configs/zshrc` → `~/.zshrc`
- `configs/init.vim` → `~/.config/nvim/init.vim`
- `configs/gitconfig` → `~/.gitconfig` (templated with user details)

## AI Integration - The Arete Framework

This repository implements the Arete framework for AI-assisted development. Key concepts:

### Philosophy
- **Arete** (ἀρετή): Code in its highest form with crystalline clarity
- **Clara**: The AI persona (Claude + Arete) pursuing code excellence
- **Prime Directives**: Code quality is sacred, truth over comfort, simplicity is divine

### Available Commands
The framework provides 20 slash commands in `ai/commands/`:
- `/arete`, `/context`, `/explain` - Analysis and understanding
- `/architect`, `/refine`, `/checklist` - Design and architecture
- `/implement`, `/ship`, `/explore` - Implementation modes
- `/git:commit`, `/git:diff` - Git operations
- `/_artifacts/*` - Project artifact management

### Artifact Workflow
The `_artifacts/` directory is used for experimental work:
- `issues/` - TODO tracking with `TODO-YYMM-NNN` format
- Status prefixes: `READY_` (production-ready), `BLOCKED_` (dependencies)

## Development Patterns

### Adding Packages
Edit arrays in `lib/packages.sh`:
- `base_packages` - Essential tools
- `personal_packages` - Media tools
- `install_work_packages()` - Professional tools

### Adding Configurations
1. Create file in `configs/` without leading dot
2. Add to `config_mappings` array in `install.sh`
3. System automatically creates symlinks

### Shell Customization
- Add `.sh` files to `scripts/aliases/` for new aliases
- Add `.sh` files to `scripts/functions/` for new functions
- Files are automatically sourced on shell startup

### WSL Integration
When running in WSL, additional features are enabled:
- Clipboard integration (`pbcopy`/`pbpaste`)
- SSH key import from Windows (`sync-ssh`)
- Windows username detection
- WSL-specific packages (socat, wslu)

## Important Notes

1. **Theme System**: Always run `./scripts/update-configs.sh` after theme changes to ensure proper configuration
2. **Git Config**: The `.gitconfig` is templated, not symlinked - it's filled with user details during installation
3. **Validation**: Use `./scripts/validate-install.sh` to verify installation completeness
4. **Backups**: Original files are backed up to `~/.dotfiles_backup_YYYYMMDD_HHMMSS/`
5. **Docker**: Included in base installation with proper group setup