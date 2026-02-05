#!/bin/bash
# Simplified Dotfiles Installation Script
# Clean, direct installation without complexity theater

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load core library (contains all functions)
source "$SCRIPT_DIR/lib.sh"

# Configuration
CONFIGS_DIR="$SCRIPT_DIR/configs"
DOTFILES_DIR="$SCRIPT_DIR"

# Installation options
INSTALL_TIER="config"  # Default tier: config, shell, dev, full
INSTALL_PERSONAL=false
FORCE_OVERWRITE=false
SHOW_HELP=false
DRY_RUN=false

# Configuration mappings using associative array
declare -A CONFIG_MAP=(
    # Simple symlinks
    [bashrc]="$HOME/.bashrc:symlink"
    [zshrc]="$HOME/.zshrc:symlink"
    [profile]="$HOME/.profile:symlink"
    [tmux.conf]="$HOME/.tmux.conf:symlink"
    [editorconfig]="$HOME/.editorconfig:symlink"
    [ripgreprc]="$HOME/.ripgreprc:symlink"
    [init.vim]="$HOME/.config/nvim/init.vim:symlink"
    [config/bat]="$HOME/.config/bat:directory"
    [config/fd]="$HOME/.config/fd:directory"
    
    # Special handling
    [gitconfig]="$HOME/.gitconfig:template"
)

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config|--sync)
                INSTALL_TIER="config"
                shift
                ;;
            --shell)
                INSTALL_TIER="shell"
                shift
                ;;
            --dev)
                INSTALL_TIER="dev"
                shift
                ;;
            --full|--work)
                INSTALL_TIER="full"
                shift
                ;;
            --personal)
                INSTALL_PERSONAL=true
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                SHOW_HELP=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                SHOW_HELP=true
                shift
                ;;
        esac
    done
}

# Check if current tier includes the required tier level
tier_includes() {
    local required="$1"
    case "$INSTALL_TIER" in
        full) return 0 ;;
        dev) [[ "$required" != "full" ]] ;;
        shell) [[ "$required" == "config" || "$required" == "shell" ]] ;;
        config) [[ "$required" == "config" ]] ;;
    esac
}

# Show help information
show_help() {
    cat << EOF
Dotfiles Installation Script - Tiered Installation System

USAGE:
    ./setup.sh [TIER] [OPTIONS]

TIERS (cumulative - each tier includes all previous tiers):
    --config, --sync    Symlinks only. Zero installs. No sudo required.
                        Creates symlinks for all configuration files.

    --shell             Config + modern CLI tools. Requires sudo.
                        Adds: starship, eza, bat, fd, ripgrep, fzf, zoxide

    --dev               Shell + development tools. Requires sudo.
                        Adds: neovim, lazygit, tmux

    --full, --work      Dev + full environment. Requires sudo.
                        Adds: NVM, pyenv, Docker, Azure CLI, Claude Code

MODIFIERS:
    --personal          Add media tools (ffmpeg, yt-dlp) to any tier

OPTIONS:
    --force             Force overwrite existing configs
    --dry-run           Preview actions without making changes
    --help              Show this help message

EXAMPLES:
    ./setup.sh                       # Default: config tier (symlinks only)
    ./setup.sh --config              # Explicit config tier
    ./setup.sh --shell               # Modern shell experience
    ./setup.sh --dev                 # Full development setup
    ./setup.sh --full                # Complete work environment
    ./setup.sh --full --personal     # Everything including media tools
    ./setup.sh --work                # Alias for --full (backwards compatible)
    ./setup.sh --shell --dry-run     # Preview shell tier installation

TIER SUMMARY:
    ┌──────────┬─────────────────────────────────────────────────┬───────────┐
    │ Tier     │ What It Installs                                │ Sudo?     │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ config   │ Symlinks only (zero installs)                   │ No        │
    │ shell    │ + starship, eza, bat, fd, ripgrep, fzf, zoxide  │ Yes       │
    │ dev      │ + neovim, lazygit, tmux                         │ Yes       │
    │ full     │ + NVM, pyenv, Docker, Azure CLI, Claude Code    │ Yes       │
    └──────────┴─────────────────────────────────────────────────┴───────────┘

The script will:
1. Verify system requirements
2. Install packages based on selected tier
3. Create symlinks for all configuration files
4. Setup WSL integration if running on WSL

All configuration files are backed up before being replaced.
EOF
}


# Phase 1: System Verification
phase_verify_system() {
    log "Phase 1: System Verification"

    # Check Ubuntu - soft requirement for config tier, hard for others
    if ! command -v lsb_release >/dev/null 2>&1; then
        if tier_includes "shell"; then
            error "This script requires Ubuntu for package installation"
            exit 1
        else
            warn "Not running on Ubuntu - proceeding with config-only mode"
        fi
    fi

    # Check basic tools that should exist
    for cmd in curl wget git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if tier_includes "shell"; then
                error "Required command not found: $cmd"
                exit 1
            else
                warn "Command not found: $cmd (not required for config tier)"
            fi
        fi
    done

    detect_environment

    # Generate locale if not present (skip for config tier - requires sudo)
    if tier_includes "shell" && [[ "$DRY_RUN" != "true" ]]; then
        if ! locale -a | grep -qi "en_US.utf8"; then
            log "Generating en_US.UTF-8 locale..."
            safe_sudo locale-gen en_US.UTF-8
            safe_sudo update-locale LANG=en_US.UTF-8
            success "Locale generated"
        fi
    fi

    success "System verification complete"
}

# Phase 2: Package Installation
phase_install_packages() {
    log "Phase 2: Package Installation"

    # Skip entirely for config tier
    if ! tier_includes "shell"; then
        log "Config tier: skipping package installation"
        success "Package installation skipped (config tier)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install packages for tier: $INSTALL_TIER"

        # Shell tier packages
        log "  Shell tier packages:"
        log "    - APT: git, build-essential, zsh, bat, fd-find, ripgrep, fzf, httpie, htop, tree, python3-pip, pipx"
        is_wsl && log "    - WSL: socat, wslu"
        log "    - Scripts: starship, eza, zoxide"

        # Dev tier packages
        if tier_includes "dev"; then
            log "  Dev tier packages:"
            log "    - Scripts: neovim, lazygit"
            log "    - APT: tmux"
        fi

        # Full tier packages
        if tier_includes "full"; then
            log "  Full tier packages:"
            log "    - Scripts: NVM, pyenv, Claude Code"
            log "    - APT: Azure CLI, python3-dev, python3-venv"
            log "    - Docker"
        fi

        # Personal packages
        [[ "$INSTALL_PERSONAL" == "true" ]] && log "  Personal: ffmpeg, yt-dlp"
    else
        # Shell tier: modern CLI tools
        install_shell_tier_packages

        # Dev tier: development tools
        if tier_includes "dev"; then
            install_dev_tier_packages
        fi

        # Full tier: complete environment
        if tier_includes "full"; then
            install_full_tier_packages
        fi

        # Personal packages (any tier)
        [[ "$INSTALL_PERSONAL" == "true" ]] && install_personal_packages
    fi

    success "Package installation complete"
}

# Phase 3: Configuration and Validation
phase_setup_configs() {
    log "Phase 3: Configuration and Validation"
    
    # Single backup directory for this installation
    local backup_dir
    backup_dir=$(create_backup_dir)
    log "Backup directory: $backup_dir"
    
    # Process configurations
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would process configurations:"
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target="${mapping%%:*}"
            local type="${mapping##*:}"
            if [[ -e "$target" ]]; then
                if [[ -L "$target" ]]; then
                    log "  ↻ $target (symlink exists - would update)"
                else
                    log "  ⚠️  $target (file exists - would backup)"
                fi
            else
                log "  ✓ $target (would create $type)"
            fi
        done
        is_wsl && log "[DRY RUN] Would setup WSL clipboard integration and SSH keys"
    else
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target="${mapping%%:*}"
            local type="${mapping##*:}"
            local source="$CONFIGS_DIR/$config"
            
            case "$type" in
                symlink)
                    process_symlink "$source" "$target" "$backup_dir"
                    ;;
                directory)
                    process_directory "$source" "$target" "$backup_dir"
                    ;;
                template)
                    process_template "$source" "$target" "$backup_dir"
                    ;;
                *)
                    error "Unknown config type: $type for $config"
                    ;;
            esac
        done
    fi
    
    # WSL-specific setup
    if is_wsl && [[ "$DRY_RUN" != "true" ]]; then
        setup_wsl_clipboard
        import_windows_ssh_keys
    fi
    
    
    # Cleanup
    cleanup_old_backups 10

    success "Configuration complete"
}

# Process symlink configuration
process_symlink() {
    local source="$1" target="$2" backup_dir="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would link $source -> $target"
        return 0
    fi
    
    # Create parent directory if needed
    local parent_dir="$(dirname "$target")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir"
    fi
    
    safe_symlink "$source" "$target" "$backup_dir"
}

# Process directory configuration
process_directory() {
    local source="$1" target="$2" backup_dir="$3"
    process_symlink "$source" "$target" "$backup_dir"
}

# Process template configuration
process_template() {
    local source="$1" target="$2" backup_dir="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would process git config template"
        return 0
    fi

    process_git_config "$source" "$target" "$backup_dir" "$FORCE_OVERWRITE"
}


# Main installation workflow
run_installation() {
    phase_verify_system
    phase_install_packages
    phase_setup_configs

    # Success message
    echo
    success "Dotfiles installation complete! (tier: $INSTALL_TIER)"
    echo

    # Post-installation instructions
    local needs_restart=false

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Check if Docker group was added (full tier only)
    if tier_includes "full" && command -v docker >/dev/null 2>&1; then
        if grep "^docker:" /etc/group | grep -q "\b$USER\b"; then
            if ! groups | grep -q docker; then
                echo "* Docker group membership requires restart"
                needs_restart=true
            fi
        fi
    fi

    # Check if NVM was installed (full tier only)
    local nvm_installed=false
    if tier_includes "full" && [[ -d "$HOME/.nvm" ]]; then
        nvm_installed=true
    fi

    # Restart recommendation based on tier
    local step=1
    if tier_includes "shell"; then
        echo "$step. Restart your shell session:"
        if is_wsl; then
            echo "   - Type 'exit' then reopen WSL, OR"
            echo "   - From PowerShell/CMD: wsl --terminate Ubuntu"
        else
            echo "   - Type 'exit' then reconnect to your terminal"
        fi
        if [[ "$needs_restart" == "true" ]]; then
            echo "   (Required for Docker group and locale changes)"
        else
            echo "   (Recommended for locale and shell changes)"
        fi
        echo
        ((step++))
    fi

    echo "$step. Verify installation:"
    echo "   ./bin/check-setup"
    echo
    ((step++))

    if [[ "$nvm_installed" == "true" ]]; then
        echo "$step. Test Node.js/npm:"
        echo "   node --version && npm --version"
        echo
        ((step++))
    fi

    echo "$step. Optionally switch theme:"
    echo "   ./bin/theme-switcher"

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main entry point
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    # Show banner
    echo "Dotfiles Installation"
    echo "===================================="
    echo "Target: Ubuntu (including WSL)"
    echo "Tier: $INSTALL_TIER$([ "$INSTALL_PERSONAL" = "true" ] && echo " + personal")"
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    # Run installation
    run_installation
}

# Execute main function
main "$@"