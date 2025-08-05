#!/bin/bash

# =============================================================================
# Update Configs Script - Refresh configuration files without full installation
# =============================================================================
# This script updates all configuration file symlinks from the dotfiles repo
# without reinstalling packages or modifying the shell environment.
#
# Usage: ./scripts/update-configs.sh [--force]
#        --force  Overwrite existing files (creates backups)
# =============================================================================

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source core functions
source "$DOTFILES_DIR/lib/core.sh"

# Configuration variables
CONFIGS_DIR="$DOTFILES_DIR/configs"
FORCE_OVERWRITE=false

# ==============================================================================
# Parse Arguments
# ==============================================================================

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_OVERWRITE=true
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo ""
            echo "Options:"
            echo "  --force    Overwrite existing files (creates backups)"
            echo ""
            echo "Updates all configuration file symlinks from the dotfiles repository"
            echo "without reinstalling packages or modifying the shell environment."
            exit 0
            ;;
        *)
            warn "Unknown argument: $arg"
            ;;
    esac
done

# ==============================================================================
# Configuration Mappings
# ==============================================================================

# Define all config file mappings (source:destination)
config_mappings=(
    # Shell configurations
    "$CONFIGS_DIR/bashrc:$HOME/.bashrc"
    "$CONFIGS_DIR/zshrc:$HOME/.zshrc"
    
    # Editor configurations  
    "$CONFIGS_DIR/init.vim:$HOME/.config/nvim/init.vim"
    "$CONFIGS_DIR/editorconfig:$HOME/.editorconfig"
    
    # Terminal configurations
    "$CONFIGS_DIR/tmux.conf:$HOME/.tmux.conf"
    
    # Development tools
    "$CONFIGS_DIR/gitconfig:$HOME/.gitconfig"
)

# Handle config subdirectories
config_subdirs=(
    "config/bat:.config/bat"
    "config/fd:.config/fd"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

# Create symlink with backup support
create_config_symlink() {
    local src="$1"
    local dest="$2"
    
    # Create parent directory if needed
    local dest_dir="$(dirname "$dest")"
    if [[ ! -d "$dest_dir" ]]; then
        log "Creating directory: $dest_dir"
        mkdir -p "$dest_dir"
    fi
    
    # Handle existing files
    if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ "$FORCE_OVERWRITE" == "true" ]]; then
            backup_file "$dest"
            rm -f "$dest"
        else
            if [[ -L "$dest" ]] && [[ "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
                log "Symlink already correct: $dest"
                return 0
            else
                warn "File exists: $dest (use --force to overwrite)"
                return 1
            fi
        fi
    fi
    
    # Create symlink
    if ln -s "$src" "$dest"; then
        success "Created symlink: $dest -> $src"
        return 0
    else
        error "Failed to create symlink: $dest"
        return 1
    fi
}

# ==============================================================================
# Main Update Process
# ==============================================================================

main() {
    echo
    echo "========================================"
    echo "Updating Configuration Files"
    echo "========================================"
    
    detect_environment
    
    # Counter for success/failure tracking
    success_count=0
    failure_count=0
    
    log "Updating configuration symlinks..."
    
    # Process main config files
    for mapping in "${config_mappings[@]}"; do
        IFS=':' read -r src dest <<< "$mapping"
        # log "Processing: $src -> $dest"  # Uncomment for debugging
        
        # Special handling for gitconfig (template)
        if [[ "$dest" == "$HOME/.gitconfig" ]] && [[ ! -f "$dest" ]]; then
            log "Skipping .gitconfig - run full installer to set up git configuration"
            continue
        fi
        
        if [[ -f "$src" ]]; then
            if create_config_symlink "$src" "$dest"; then
                success_count=$((success_count + 1))
                # log "Success count: $success_count"  # Uncomment for debugging
            else
                failure_count=$((failure_count + 1))
                # log "Failure count: $failure_count"  # Uncomment for debugging
            fi
        else
            warn "Source file not found: $src"
            failure_count=$((failure_count + 1))
        fi
    done
    
    # log "Finished processing main config files"  # Uncomment for debugging
    
    # Process config subdirectories
    for mapping in "${config_subdirs[@]}"; do
        IFS=':' read -r src_rel dest_rel <<< "$mapping"
        local src="$CONFIGS_DIR/$src_rel"
        local dest="$HOME/$dest_rel"
        
        if [[ -d "$src" ]]; then
            if create_config_symlink "$src" "$dest"; then
                success_count=$((success_count + 1))
            else
                failure_count=$((failure_count + 1))
            fi
        else
            warn "Source directory not found: $src"
            failure_count=$((failure_count + 1))
        fi
    done
    
    # Create neovim theme.vim if it doesn't exist
    local nvim_theme_file="$HOME/.config/nvim/theme.vim"
    if [[ ! -f "$nvim_theme_file" ]]; then
        log "Creating neovim theme.vim file..."
        mkdir -p "$(dirname "$nvim_theme_file")"
        cat > "$nvim_theme_file" << 'EOF'
" Default theme configuration for neovim
" This file is sourced by init.vim for theme settings
try
    let g:gruvbox_material_background = 'medium'
    let g:gruvbox_material_better_performance = 1
    colorscheme gruvbox-material
catch
    colorscheme desert
endtry
EOF
        success "Created neovim theme.vim with default theme"
        success_count=$((success_count + 1))
    fi
    
    # Summary
    echo
    echo "========================================"
    echo "Update Summary"
    echo "========================================"
    success "Updated: $success_count configurations"
    if [[ $failure_count -gt 0 ]]; then
        warn "Failed: $failure_count configurations"
    fi
    
    # Remind about reloading
    echo
    log "To apply changes to your current shell, run: ${CYAN}reload${RESET}"
    
    # Check if we should create gitconfig
    if [[ ! -f "$HOME/.gitconfig" ]]; then
        echo
        warn "Note: .gitconfig not found. Run the full installer to set up git configuration."
    fi
    
    # Cleanup old backups (keep last 10 individual file backups)
    cleanup_old_backups 10
    
    # Return appropriate exit code
    if [[ $failure_count -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Run main function and capture exit status
main
MAIN_EXIT_CODE=$?

# Exit with main's exit code
exit $MAIN_EXIT_CODE