#!/bin/bash
# Simplified Dotfiles Installation Script
# Ubuntu-only support, human-readable, well-engineered
# Usage: ./install.sh [--work] [--personal] [--force] [--help]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load simplified modules
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/packages.sh"

# Configuration
CONFIGS_DIR="$SCRIPT_DIR/configs"
DOTFILES_DIR="$SCRIPT_DIR"
export DOTFILES_DIR

# Command line flags
INSTALL_WORK=false
INSTALL_PERSONAL=false
FORCE_OVERWRITE=false
SHOW_HELP=false

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
    --work          Install professional development tools (includes Azure CLI)
    --personal      Install personal/media tools  
    --force         (Legacy option - configs are always safely backed up)
    --help          Show this help message

EXAMPLES:
    ./install.sh                    # Install base packages only
    ./install.sh --work             # Install base + work tools
    ./install.sh --work --personal  # Install everything

The script will:
1. Install essential packages (always)
2. Install Docker (always)
3. Install work tools if --work specified (includes Azure CLI)
4. Install personal tools if --personal specified
5. Create symlinks for all configuration files
6. Setup WSL integration if running on WSL

All configuration files are backed up before being replaced.
EOF
}

# Create configuration symlinks
create_config_symlinks() {
    log "Creating configuration symlinks..."
    
    local backup_dir
    if ! backup_dir=$(create_backup_dir); then
        error "Failed to create backup directory"
        return 1
    fi
    log "Using backup directory: $backup_dir"
    
    # Configuration files mapping: source_name:target_name
    local config_mappings=(
        "bashrc:.bashrc"
        "zshrc:.zshrc"
        "init.vim:.config/nvim/init.vim"
        "tmux.conf:.tmux.conf"
        "gitconfig:.gitconfig"
        "editorconfig:.editorconfig"
        "profile:.profile"
        "ripgreprc:.ripgreprc"
    )
    
    # Create neovim config directory if needed
    mkdir -p "$HOME/.config/nvim"
    
    # Handle regular config files
    for mapping in "${config_mappings[@]}"; do
        local source_name="${mapping%:*}"
        local target_name="${mapping#*:}"
        local source="$CONFIGS_DIR/$source_name"
        local target="$HOME/$target_name"
        
        if [[ -f "$source" ]]; then
            if [[ "$source_name" == "gitconfig" ]]; then
                # Special handling for git config template
                process_git_config "$source" "$target" "$backup_dir"
            else
                safe_symlink "$source" "$target" "$backup_dir"
            fi
        else
            warn "Config file not found: $source"
        fi
    done
    
    # Handle directories
    local dir_mappings=(
        "config:.config"
    )
    
    for mapping in "${dir_mappings[@]}"; do
        local source_name="${mapping%:*}"
        local target_name="${mapping#*:}"
        local source="$CONFIGS_DIR/$source_name"
        local target="$HOME/$target_name"
        
        if [[ -d "$source" ]]; then
            safe_symlink "$source" "$target" "$backup_dir"
        else
            warn "Config directory not found: $source"
        fi
    done
    
    # Add DOTFILES_DIR to shell configs for runtime
    log "Setting DOTFILES_DIR in shell configurations..."
    for shell_config in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -L "$shell_config" ]]; then
            # Get the actual config file that the symlink points to
            local actual_config="$(readlink -f "$shell_config")"
            if [[ -f "$actual_config" ]]; then
                # Check if DOTFILES_DIR is already set in the file
                if ! grep -q "^export DOTFILES_DIR=" "$actual_config"; then
                    # Add DOTFILES_DIR export at the beginning of the file
                    local temp_file=$(mktemp)
                    echo "# Set DOTFILES_DIR for this installation" > "$temp_file"
                    echo "export DOTFILES_DIR=\"$DOTFILES_DIR\"" >> "$temp_file"
                    echo "" >> "$temp_file"
                    cat "$actual_config" >> "$temp_file"
                    mv "$temp_file" "$actual_config"
                    success "Added DOTFILES_DIR to $(basename "$shell_config")"
                else
                    log "DOTFILES_DIR already set in $(basename "$shell_config")"
                fi
            fi
        fi
    done
    
    success "Configuration symlinks created"
}

# Setup shell integration
setup_shell_integration() {
    log "Setting up shell integration..."
    
    # Ensure aliases and functions are sourced
    local shell_dirs=("$DOTFILES_DIR/scripts/aliases" "$DOTFILES_DIR/scripts/functions")
    
    for dir in "${shell_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            for script in "$dir"/*.sh; do
                # Skip if glob doesn't match any files
                [[ -f "$script" ]] || continue
                log "Shell script available: $(basename "$script")"
            done
        fi
    done
    
    success "Shell integration configured (restart shell to activate)"
}

# Validate required functions are available
validate_required_functions() {
    local required_functions=(
        "validate_prerequisites" "detect_environment" "install_base_packages"
        "install_work_packages" "install_personal_packages" "setup_zsh_environment"
        "create_backup_dir" "safe_symlink" "process_git_config"
        "setup_wsl_clipboard" "import_windows_ssh_keys" "setup_npm_global"
        "validate_installation"
    )
    
    local missing_functions=()
    for func in "${required_functions[@]}"; do
        if ! declare -f "$func" >/dev/null 2>&1; then
            missing_functions+=("$func")
        fi
    done
    
    if [[ ${#missing_functions[@]} -gt 0 ]]; then
        error "Missing required functions: ${missing_functions[*]}"
        error "Please check lib/core.sh and lib/packages.sh are complete"
        exit 1
    fi
}

# Main installation workflow
run_installation() {
    # Phase 0: Function Validation
    validate_required_functions
    
    # Phase 1: Validation
    validate_prerequisites
    detect_environment
    
    # Phase 2: Package Installation
    install_base_packages
    
    if [[ "$INSTALL_WORK" == "true" ]]; then
        install_work_packages
    fi
    
    if [[ "$INSTALL_PERSONAL" == "true" ]]; then
        install_personal_packages
    fi
    
    # Phase 3: Shell Environment Setup
    setup_zsh_environment
    
    # Phase 4: Configuration
    create_config_symlinks
    setup_shell_integration
    
    # Phase 5: WSL Setup (if applicable)
    if [[ "$IS_WSL" == "true" ]]; then
        setup_wsl_clipboard
        import_windows_ssh_keys
    fi
    
    # Phase 6: Final Setup
    setup_npm_global
    
    # Phase 7: Validation
    validate_installation
    
    # Success message
    echo
    success "🎉 Dotfiles installation completed successfully!"
    echo
    log "Next steps:"
    log "  1. To use Zsh: chsh -s $(which zsh) && exec zsh"
    log "  2. Configure Powerlevel10k: p10k configure"
    log "  3. Or stay with Bash: source ~/.bashrc"
    log "  4. Run 'reload' command to refresh your environment"
    if [[ "$INSTALL_WORK" == "true" ]]; then
        log "  5. Login to Azure: az login"
    fi
    if [[ "$IS_WSL" == "true" ]]; then
        log "  6. SSH keys imported from Windows"
        log "  7. Clipboard integration (pbcopy/pbpaste) ready"
    fi
    echo
}

# Main function
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