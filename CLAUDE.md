# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Commands

### Installation & Setup
```bash
# Base installation (essential tools only)
./install.sh

# Full installation with work/personal tools
./install.sh --work --personal

# Update configurations without reinstalling packages
./scripts/update-configs.sh
```

### Validation & Testing
```bash
# Validate installation
./scripts/validate-install.sh --verbose

# Fix common issues automatically
./scripts/validate-install.sh --fix

# Check specific category
./scripts/validate-install.sh --category docker
```

### Development Commands
```bash
# Reload shell configuration
reload

# Switch themes interactively
./scripts/theme-switcher.sh

# List available themes
themes
```

## High-Level Architecture

This is a **Ubuntu-focused dotfiles repository** designed with the Arete philosophy: pursuing code in its highest form where every line serves its purpose with crystalline clarity.

### Core Design Principles
- **Ubuntu-only**: No cross-platform complexity (70% code reduction from original)
- **Human-readable**: Any developer can understand in 20 minutes
- **Security-first**: HTTPS downloads, checksum verification, fail-safe operations
- **Non-destructive**: Automatic backups before any changes
- **Modular**: Clear separation between core utilities, packages, and validation

### Directory Structure
- `install.sh` - Main entry point, orchestrates installation
- `lib/` - Core functionality (core.sh, packages.sh, validation.sh)
- `configs/` - Visible config files without leading dots for easy discovery
- `scripts/` - Utilities for theme switching, config updates, validation
- `artifacts/` - Temporary development work before promotion to production

### Key Architectural Decisions
1. **Symlink Management**: All configs are symlinked from `configs/` to home directory with automatic backup
2. **Package Sets**: Base (essential), Work (dev tools), Personal (media) - clearly separated
3. **Validation System**: Pre/post installation checks with repair capabilities
4. **Theme System**: 5 pre-configured themes with hot-swappable configuration
5. **WSL Integration**: Automatic detection and setup for Windows Subsystem for Linux

### Development Workflow
The repository follows the artifacts pattern (`ai/workflow.md`):
- Experimental work in `artifacts/`
- Production code in appropriate directories
- Temporal naming: `YYMMDD_HHMM_description.ext`
- Issue tracking: `artifacts/issues/TODO-YYMM-NNN_description.md`

## Project Edicts

1. **Simplicity Over Features**: If a feature adds complexity without clear benefit, it doesn't belong
2. **Ubuntu-Only**: No macOS, no Fedora, no Arch - just Ubuntu/Debian
3. **Visible Configs**: Store configs without leading dots in `configs/` directory
4. **Fail-Safe Operations**: Every destructive operation must have a backup
5. **Human-Readable Code**: Avoid clever bash tricks that sacrifice clarity

## Quality Metrics

- Installation must complete in under 2 minutes (excluding package downloads)
- Validation script must detect 100% of missing dependencies
- All shell scripts must pass shellcheck
- Zero external dependencies for core functionality (only apt/snap packages)

## Common Development Tasks

When modifying this repository:
1. Always run `./scripts/validate-install.sh` after changes
2. Test installation in a fresh Ubuntu container: `docker run -it ubuntu:latest`
3. Update `scripts/aliases/` or `scripts/functions/` for new shell utilities
4. Follow the Arete philosophy - delete more than you add

Remember: This is a dotfiles repository that values clarity, simplicity, and reliability above all else.