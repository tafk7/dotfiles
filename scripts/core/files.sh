#!/bin/bash
# File operations: backup, symlinks, configuration management

# Template processing for configuration files
process_git_config_template() {
    local template_file="$DOTFILES_DIR/configs/.gitconfig"
    local target_file="$HOME/.gitconfig"
    
    # Check if template needs processing
    if grep -q "__GIT_USER_NAME__\|__GIT_USER_EMAIL__" "$template_file" 2>/dev/null; then
        log "Git configuration requires setup..."
        
        # Get user information
        local git_name git_email
        
        # Try to get existing git config first
        git_name=$(git config --global user.name 2>/dev/null || echo "")
        git_email=$(git config --global user.email 2>/dev/null || echo "")
        
        # Prompt for missing information
        if [[ -z "$git_name" ]]; then
            read -p "Enter your full name for Git: " git_name
        fi
        
        if [[ -z "$git_email" ]]; then
            read -p "Enter your email for Git: " git_email
        fi
        
        # Validate inputs
        if [[ -z "$git_name" || -z "$git_email" ]]; then
            warn "Git configuration skipped - name and email required"
            return 1
        fi
        
        # Create processed config file
        sed -e "s/__GIT_USER_NAME__/$git_name/g" \
            -e "s/__GIT_USER_EMAIL__/$git_email/g" \
            "$template_file" > "$target_file"
        
        success "Git configuration created with name: $git_name, email: $git_email"
        return 0
    fi
    
    # No template processing needed, create symlink normally
    return 1
}

# Create backup of existing dotfiles
create_backup() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    local files=(".gitconfig" ".profile" ".editorconfig" ".ripgreprc" ".vimrc" ".vim" ".tmux.conf" ".zshrc" ".ssh/config" ".config/bat" ".config/fd")
    for file in "${files[@]}"; do
        if [[ -e "$HOME/$file" ]]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$file")"
            cp -r "$HOME/$file" "$BACKUP_DIR/$file"
            log "Backed up $file"
        fi
    done
}

# Safe symlink creation function
create_safe_symlink() {
    local source="$1"
    local target="$2"
    local config_name="$(basename "$target")"
    
    # If target doesn't exist, create symlink
    if [[ ! -e "$target" ]]; then
        ln -s "$source" "$target"
        success "Created symlink for $config_name"
        return 0
    fi
    
    # If it's already our symlink, skip
    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        log "$config_name already linked correctly"
        return 0
    fi
    
    # Handle existing files/directories
    if [[ "$FORCE_MODE" == true ]]; then
        # Remove existing and create symlink
        rm -rf "$target"
        ln -s "$source" "$target"
        success "Force-linked $config_name"
        return 0
    fi
    
    # Interactive mode - ask user what to do
    warn "$config_name already exists"
    echo "Choose action:"
    echo "  1) Skip (leave existing)"
    echo "  2) Backup and replace"
    echo "  3) Remove and replace"
    
    while true; do
        read -p "Enter choice [1-3]: " choice
        case $choice in
            1)
                log "Skipped $config_name"
                return 0
                ;;
            2)
                # Backup existing
                if [[ ! -d "$BACKUP_DIR" ]]; then
                    mkdir -p "$BACKUP_DIR"
                fi
                mv "$target" "$BACKUP_DIR/$(basename "$target").$(date +%H%M%S)"
                ln -s "$source" "$target"
                success "Backed up and linked $config_name"
                return 0
                ;;
            3)
                # Remove existing
                rm -rf "$target"
                ln -s "$source" "$target"
                success "Replaced and linked $config_name"
                return 0
                ;;
            *)
                echo "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# Create symlinks for configuration files
create_symlinks() {
    log "Creating symlinks..."
    
    # Core config files with enhanced processing
    local configs=(".gitconfig" ".profile" ".editorconfig" ".ripgreprc" ".vimrc" ".tmux.conf")
    for config in "${configs[@]}"; do
        if [[ -f "$DOTFILES_DIR/configs/$config" ]]; then
            # Special handling for .gitconfig template processing
            if [[ "$config" == ".gitconfig" ]]; then
                if process_git_config_template; then
                    log "Git configuration processed from template"
                else
                    create_safe_symlink "$DOTFILES_DIR/configs/$config" "$HOME/$config"
                fi
            else
                create_safe_symlink "$DOTFILES_DIR/configs/$config" "$HOME/$config"
            fi
        else
            warn "Config file not found: $DOTFILES_DIR/configs/$config"
        fi
    done
    
    # Handle .vim directory
    if [[ -d "$DOTFILES_DIR/configs/.vim" ]]; then
        create_safe_symlink "$DOTFILES_DIR/configs/.vim" "$HOME/.vim"
    fi
    
    # Handle .zshrc if zsh is installed
    if command -v zsh >/dev/null 2>&1 && [[ -f "$DOTFILES_DIR/configs/.zshrc" ]]; then
        create_safe_symlink "$DOTFILES_DIR/configs/.zshrc" "$HOME/.zshrc"
        log "Zsh configuration linked"
    fi
    
    # Create .config directory symlinks
    setup_config_directory_links
    
    # VS Code settings
    setup_vscode_config
}

# Setup .config directory links
setup_config_directory_links() {
    mkdir -p "$HOME/.config"
    
    # Bat configuration
    if [[ -f "$DOTFILES_DIR/configs/.config/bat/config" ]]; then
        mkdir -p "$HOME/.config"
        create_safe_symlink "$DOTFILES_DIR/configs/.config/bat" "$HOME/.config/bat"
    fi
    
    # fd configuration  
    if [[ -f "$DOTFILES_DIR/configs/.config/fd/ignore" ]]; then
        mkdir -p "$HOME/.config"
        create_safe_symlink "$DOTFILES_DIR/configs/.config/fd" "$HOME/.config/fd"
    fi
}

# VS Code configuration setup
setup_vscode_config() {
    local vscode_config=""
    
    if is_wsl; then
        # WSL: Link to Windows VS Code settings if available
        local win_user=$(get_windows_username 2>/dev/null || echo "")
        local win_vscode_dir="/mnt/c/Users/$win_user/AppData/Roaming/Code/User"
        
        if [[ -n "$win_user" && -d "$win_vscode_dir" ]]; then
            vscode_config="$win_vscode_dir"
            wsl_log "Linked VS Code settings (Windows)"
        fi
    fi
    
    if [[ -z "$vscode_config" ]]; then
        # Standard Linux VS Code config
        vscode_config="$HOME/.config/Code/User"
        wsl_log "Linked VS Code settings (WSL)"
    fi
    
    if [[ -n "$vscode_config" ]]; then
        mkdir -p "$vscode_config"
        create_safe_symlink "$DOTFILES_DIR/configs/vscode/settings.jsonc" "$vscode_config/settings.json"
    fi
}