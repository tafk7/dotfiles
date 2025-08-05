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

# Configuration mappings using associative array
declare -A CONFIG_MAP=(
    # Simple symlinks
    [bashrc]="$HOME/.bashrc:symlink"
    [zshrc]="$HOME/.zshrc:symlink"
    [zshrc.minimal]="$HOME/.zshrc.minimal:symlink"
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


# Phase 0: Prerequisites
phase_prerequisites() {
    log "Checking prerequisites..."
    
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
}

# Phase 1: Package Installation
phase_packages() {
    log "Phase 1: Package Installation"
    
    install_base_packages
    [[ "$INSTALL_WORK" == "true" ]] && install_work_packages
    [[ "$INSTALL_PERSONAL" == "true" ]] && install_personal_packages
    
    success "Package installation phase complete"
}

# Phase 2: Configuration
phase_configuration() {
    log "Phase 2: Configuration"
    
    # Create backup directory
    local backup_dir
    backup_dir=$(create_backup_dir)
    log "Backup directory: $backup_dir"
    
    # Process each configuration
    for config in "${!CONFIG_MAP[@]}"; do
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
    
    success "Configuration phase complete"
}

# Process symlink configuration
process_symlink() {
    local source="$1" target="$2" backup_dir="$3"
    
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
    
    process_git_config "$source" "$target" "$backup_dir"
}

# Phase 3: Shell Integration
phase_shell_integration() {
    log "Phase 3: Shell Integration"
    
    # Setup FZF integration
    if command -v fzf >/dev/null 2>&1; then
        local fzf_base="/usr/share/doc/fzf/examples"
        if [[ -d "$fzf_base" ]]; then
            log "FZF integration files found at $fzf_base"
        else
            warn "FZF installed but integration files not found"
        fi
    fi
    
    success "Shell integration phase complete"
}

# Phase 4: WSL Setup
phase_wsl_setup() {
    if [[ "$IS_WSL" != "true" ]]; then
        log "Phase 4: WSL Setup - Skipped (not running on WSL)"
        return 0
    fi
    
    log "Phase 4: WSL Setup"
    
    setup_wsl_clipboard
    import_windows_ssh_keys
    
    success "WSL setup phase complete"
}

# Phase 5: Final Setup
phase_final_setup() {
    log "Phase 5: Final Setup"
    
    setup_npm_global
    
    # Run minimal validation checks
    log "Running setup checks..."
    "$SCRIPT_DIR/scripts/check-setup.sh"
    
    cleanup_old_backups 5
    
    success "Final setup phase complete"
}

# Main installation workflow
run_installation() {
    phase_prerequisites
    phase_packages
    phase_configuration
    phase_shell_integration
    phase_wsl_setup
    phase_final_setup
    
    # Success message
    echo
    success "🎉 Dotfiles installation complete!"
    echo
    echo "Next steps:"
    echo "1. Restart your shell or run: source ~/.bashrc"
    echo "2. For Zsh customization, run: ./scripts/setup-zsh-environment.sh"
    [[ "$IS_WSL" == "true" ]] && echo "3. Log out and back in for Docker group changes"
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
    echo
    
    # Run installation
    run_installation
}

# Execute main function
main "$@"