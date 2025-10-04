#!/bin/bash
# Simplified Dotfiles Installation Script
# Clean, direct installation without complexity theater

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load simplified modules
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/packages.sh"

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
    ./install.sh [OPTIONS]

OPTIONS:
    --work          Install professional development tools
    --personal      Install personal/media tools  
    --force         Force overwrite existing configs
    --dry-run       Preview actions without making changes
    --help          Show this help message

EXAMPLES:
    ./install.sh                    # Install base packages only
    ./install.sh --work             # Install base + work tools
    ./install.sh --work --personal  # Install everything

The script will:
1. Install essential packages (git, curl, zsh, neovim, etc.)
2. Install work tools if --work specified (Docker, Node.js, Azure CLI)
3. Install personal tools if --personal specified (ffmpeg, yt-dlp)
4. Create symlinks for all configuration files
5. Setup WSL integration if running on WSL

For Zsh customization (Oh My Zsh, themes, plugins), run:
    ./scripts/setup-zsh-environment.sh

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
        
        # Work packages (includes proper npm setup)
        if [[ "$INSTALL_WORK" == "true" ]]; then
            install_node_and_npm
            install_work_packages
        fi
        
        # Personal packages
        [[ "$INSTALL_PERSONAL" == "true" ]] && install_personal_packages
        
        # Modern tools via dedicated installers
        "$DOTFILES_DIR/scripts/install-starship.sh" || { error "Starship installation failed"; exit 1; }
        "$DOTFILES_DIR/scripts/install-eza.sh" || { error "Eza installation failed"; exit 1; }
        "$DOTFILES_DIR/scripts/install-lazygit.sh" || { error "Lazygit installation failed"; exit 1; }
        "$DOTFILES_DIR/scripts/install-zoxide.sh" || { error "Zoxide installation failed"; exit 1; }
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
    
    # NPM setup if Node.js is installed but wasn't in work packages
    if command -v npm >/dev/null 2>&1 && [[ "$INSTALL_WORK" != "true" ]]; then
        setup_npm_global
    fi
    
    # Validation
    log "Running setup validation..."
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! "$SCRIPT_DIR/scripts/check-setup.sh"; then
            error "Setup validation failed"
            exit 1
        fi
    fi
    
    # Cleanup
    cleanup_old_backups 10
    
    success "Configuration and validation complete"
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
    
    process_git_config "$source" "$target" "$backup_dir"
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
    echo "Next steps:"
    echo "1. Restart your shell or run: source ~/.bashrc"
    if [[ "$INSTALL_WORK" == "true" ]] && command -v docker >/dev/null 2>&1; then
        echo "2. Log out and back in for Docker group changes"
    fi
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