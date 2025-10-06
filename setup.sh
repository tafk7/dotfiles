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
INSTALL_WORK=false
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
            --work)
                INSTALL_WORK=true
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

# Show help information
show_help() {
    cat << EOF
Simplified Dotfiles Installation Script

USAGE:
    ./setup.sh [OPTIONS]

OPTIONS:
    --work          Install professional development tools
    --personal      Install personal/media tools  
    --force         Force overwrite existing configs
    --dry-run       Preview actions without making changes
    --help          Show this help message

EXAMPLES:
    ./setup.sh                    # Install base packages only
    ./setup.sh --work             # Install base + work tools
    ./setup.sh --work --personal  # Install everything

The script will:
1. Install essential packages (git, curl, zsh, neovim, etc.)
2. Install work tools if --work specified (Docker, Node.js, Azure CLI)
3. Install personal tools if --personal specified (ffmpeg, yt-dlp)
4. Create symlinks for all configuration files
5. Setup WSL integration if running on WSL

For Zsh customization (Oh My Zsh, themes, plugins), run:
    # Legacy setup script removed - shell environment now configured via configs/zshrc

All configuration files are backed up before being replaced.
EOF
}


# Phase 1: System Verification
phase_verify_system() {
    log "Phase 1: System Verification"

    # Check Ubuntu
    if ! command -v lsb_release >/dev/null 2>&1; then
        error "This script requires Ubuntu"
        exit 1
    fi

    # Check basic tools that should exist
    for cmd in curl wget git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done

    detect_environment

    # Generate locale if not present
    if [[ "$DRY_RUN" != "true" ]]; then
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
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install packages:"
        log "  - Core packages: git, curl, wget, build-essential"
        log "  - Development: neovim, tmux, zsh, openssh-client"
        log "  - Modern CLI: bat, fd-find, ripgrep, fzf"
        log "  - Terminal tools: glow, lazygit, httpie, htop, tree"
        log "  - Languages: python3-pip, pipx"
        is_wsl && log "  - WSL tools: socat, wslu"
        [[ "$INSTALL_WORK" == "true" ]] && log "  - Work tools: Node.js, Docker, Azure CLI"
        [[ "$INSTALL_PERSONAL" == "true" ]] && log "  - Personal tools: ffmpeg, yt-dlp"
        log "  - Additional tools via scripts: starship, eza, lazygit, zoxide"
    else
        install_base_packages  # Now includes terminal and WSL packages
        
        # Work packages
        if [[ "$INSTALL_WORK" == "true" ]]; then
            install_work_packages
            # Install NVM and Node.js
            "$DOTFILES_DIR/install/install-nvm.sh" || { error "NVM installation failed"; exit 1; }
        fi

        # Personal packages
        [[ "$INSTALL_PERSONAL" == "true" ]] && install_personal_packages

        # Modern tools via dedicated installers
        "$DOTFILES_DIR/install/install-starship.sh" || { error "Starship installation failed"; exit 1; }
        "$DOTFILES_DIR/install/install-eza.sh" || { error "Eza installation failed"; exit 1; }
        "$DOTFILES_DIR/install/install-lazygit.sh" || { error "Lazygit installation failed"; exit 1; }
        "$DOTFILES_DIR/install/install-zoxide.sh" || { error "Zoxide installation failed"; exit 1; }
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
    success "🎉 Dotfiles installation complete!"
    echo

    # Post-installation instructions
    local needs_restart=false

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Check if Docker group was added
    if [[ "$INSTALL_WORK" == "true" ]] && command -v docker >/dev/null 2>&1; then
        if grep "^docker:" /etc/group | grep -q "\b$USER\b"; then
            if ! groups | grep -q docker; then
                echo "⚠️  Docker group membership requires restart"
                needs_restart=true
            fi
        fi
    fi

    # Check if NVM was installed
    local nvm_installed=false
    if [[ "$INSTALL_WORK" == "true" ]] && [[ -d "$HOME/.nvm" ]]; then
        nvm_installed=true
    fi

    # Always recommend restart for locale changes to take effect
    echo "1. 🔄 Restart your WSL session:"
    if is_wsl; then
        echo "   • Type 'exit' then reopen WSL, OR"
        echo "   • From PowerShell/CMD: wsl --terminate Ubuntu"
    else
        echo "   • Type 'exit' then reconnect to your terminal"
    fi
    if [[ "$needs_restart" == "true" ]]; then
        echo "   (Required for Docker group and locale changes)"
    else
        echo "   (Required for locale changes to take effect)"
    fi
    echo
    echo "2. ✅ Verify installation:"
    echo "   ./bin/check-setup"
    echo
    if [[ "$nvm_installed" == "true" ]]; then
        echo "3. 🧪 Test Node.js/npm:"
        echo "   node --version && npm --version"
        echo
    fi
    echo "$(if [[ "$nvm_installed" == "true" ]]; then echo "4"; else echo "3"; fi). 🎨 Optionally switch theme:"
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
    echo "🚀 Simplified Dotfiles Installation"
    echo "===================================="
    echo "Target: Ubuntu (including WSL)"
    echo "Packages: Base$([ "$INSTALL_WORK" = "true" ] && echo " + Work")$([ "$INSTALL_PERSONAL" = "true" ] && echo " + Personal")"
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    # Run installation
    run_installation
}

# Execute main function
main "$@"