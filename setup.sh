#!/bin/bash
# Simplified Dotfiles Installation Script
# Clean, direct installation without complexity theater

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set DOTFILES_DIR before sourcing lib
DOTFILES_DIR="$SCRIPT_DIR"
export DOTFILES_DIR

# Load install library (pulls in runtime.sh + config.sh)
source "$SCRIPT_DIR/lib/install.sh"

# Installation options
INSTALL_TIER="config"  # Default tier: config, shell, dev, full
FORCE_OVERWRITE=false
FORCE_REINSTALL=false
SHOW_HELP=false
DRY_RUN=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
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
            --full)
                INSTALL_TIER="full"
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                FORCE_REINSTALL=true
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
    --config            Symlinks only. Zero installs. No sudo required.
                        Creates symlinks for all configuration files.

    --shell             Config + modern CLI tools. Requires sudo.
                        Installs binary tools via eget (starship, eza, fzf,
                        zoxide, delta, btop, glow, lazygit, uv) plus APT
                        packages (bat, fd, ripgrep, direnv).

    --dev               Shell + development tools. Requires sudo.
                        Adds: neovim, tmux

    --full              Dev + full environment. Requires sudo.
                        Adds: NVM, pyenv, poetry, Docker, Azure CLI

OPTIONS:
    --force             Force overwrite configs and reinstall tools
    --dry-run           Preview actions without making changes
    --help              Show this help message

EXAMPLES:
    ./setup.sh                       # Default: config tier (symlinks only)
    ./setup.sh --config              # Explicit config tier
    ./setup.sh --shell               # Modern shell experience
    ./setup.sh --dev                 # Full development setup
    ./setup.sh --full                # Complete work environment
    ./setup.sh --shell --dry-run     # Preview shell tier installation

TIER SUMMARY:
    ┌──────────┬─────────────────────────────────────────────────┬───────────┐
    │ Tier     │ What It Installs                                │ Sudo?     │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ config   │ Symlinks only (zero installs)                   │ No        │
    │ shell    │ + eget, starship, eza, fzf, zoxide, delta,      │ Yes       │
    │          │   btop, glow, lazygit, uv, bat, fd, ripgrep     │           │
    │ dev      │ + neovim, tmux                                │ Yes       │
    │ full     │ + NVM, pyenv, poetry, Docker, Azure CLI         │ Yes       │
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
            if safe_sudo locale-gen en_US.UTF-8 && safe_sudo update-locale LANG=en_US.UTF-8; then
                success "Locale generated"
            else
                warn "Locale generation failed - some shell features may not work correctly"
            fi
        fi
    fi

    success "System verification complete"
}

# Phase 2: Package Installation
phase_install_packages() {
    log "Phase 2: Package Installation"

    if ! tier_includes "shell"; then
        log "Config tier: skipping package installation"
        return 0
    fi

    install_shell_packages

    if tier_includes "dev"; then
        install_dev_packages
    fi

    if tier_includes "full"; then
        install_full_packages
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
            local source="$(config_source_path "$config")"
            
            case "$type" in
                symlink)
                    process_symlink "$source" "$target" "$backup_dir"
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
        source "$DOTFILES_DIR/shell/functions/wsl.sh"
        import_windows_ssh_keys
    fi

    # Initialize default theme if none is set (theme-switcher owns the default)
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ ! -f "$HOME/.config/dotfiles/current-theme" ]]; then
            log "[DRY RUN] Would initialize default theme"
        fi
    else
        "$DOTFILES_DIR/bin/theme-switcher" --init
    fi

    # Write install-time environment to ~/.config/dotfiles/env
    write_dotfiles_env

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

    # SSH directory requires strict permissions
    if [[ "$parent_dir" == *"/.ssh"* || "$parent_dir" == *"/.ssh" ]]; then
        chmod 700 "$parent_dir"
        mkdir -p "$parent_dir/sockets"
        chmod 700 "$parent_dir/sockets"
    fi
    
    safe_symlink "$source" "$target" "$backup_dir"
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

    # Show what happened with tool installs
    print_install_summary

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
    echo "   ./bin/verify"
    echo
    ((step++))

    if [[ "$nvm_installed" == "true" ]]; then
        echo "$step. Test Node.js/npm:"
        echo "   node --version && npm --version"
        echo
        ((step++))
    fi

    echo "$step. Switch theme (default: gruvbox):"
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
    echo "Tier: $INSTALL_TIER"
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    # Run installation
    run_installation
}

# Execute main function
main "$@"