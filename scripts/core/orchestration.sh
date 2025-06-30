#!/bin/bash
# Installation orchestration and workflow management

# Main installation workflow
run_installation() {
    log "Starting dotfiles installation..."
    
    # Phase 0: Pre-installation validation
    if ! pre_install_validation; then
        error "Pre-installation validation failed"
        exit 1
    fi
    
    # Phase 1: System preparation
    update_system
    create_backup
    
    # Phase 2: Base setup (always installed)
    run_base_setup
    
    # Phase 3: Optional components
    if [[ "$INSTALL_WORK" == true ]]; then
        run_work_setup
    fi
    
    if [[ "$INSTALL_PERSONAL" == true ]]; then
        run_personal_setup
    fi
    
    if [[ "$INSTALL_AI" == true ]]; then
        run_ai_setup
    fi
    
    # Phase 4: Configuration and integration
    create_symlinks
    setup_shell_integration
    setup_ssh
    
    # Phase 5: WSL-specific setup
    if is_wsl; then
        setup_wsl
    fi
    
    # Phase 6: Finalization
    finalize_installation
    
    # Phase 7: Post-installation validation
    post_install_validation
    
    success "Installation completed successfully!"
    show_next_steps
}

# Run base setup
run_base_setup() {
    log "Running base setup..."
    
    if [[ -f "$DOTFILES_DIR/setup/base_setup.sh" ]]; then
        source "$DOTFILES_DIR/setup/base_setup.sh"
        install_base_packages
    else
        error "Base setup script not found"
        exit 1
    fi
}

# Run work setup
run_work_setup() {
    log "Running work setup..."
    
    if [[ -f "$DOTFILES_DIR/setup/work_setup.sh" ]]; then
        source "$DOTFILES_DIR/setup/work_setup.sh"
        install_work_packages
    else
        warn "Work setup script not found, skipping work packages"
    fi
}

# Run personal setup
run_personal_setup() {
    log "Running personal setup..."
    
    if [[ -f "$DOTFILES_DIR/setup/personal_setup.sh" ]]; then
        source "$DOTFILES_DIR/setup/personal_setup.sh"
        install_personal_packages
    else
        warn "Personal setup script not found, skipping personal packages"
    fi
}

# Run AI setup
run_ai_setup() {
    log "Running AI setup..."
    
    if [[ -f "$DOTFILES_DIR/setup/ai_setup.sh" ]]; then
        source "$DOTFILES_DIR/setup/ai_setup.sh"
        install_ai_packages
    else
        warn "AI setup script not found, skipping AI tools"
    fi
}

# Setup shell integration
setup_shell_integration() {
    log "Setting up shell integration..."
    
    # Source our custom scripts in shell configuration
    local shell_config="$HOME/.bashrc"
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_config="$HOME/.zshrc"
    fi
    
    # Add our scripts to shell config if not already present
    if ! grep -q "# Dotfiles integration" "$shell_config" 2>/dev/null; then
        cat >> "$shell_config" << 'EOF'

# Dotfiles integration
if [[ -d "$HOME/.dotfiles/scripts" ]]; then
    # Load aliases
    for alias_file in "$HOME/.dotfiles/scripts/aliases"/*.sh; do
        [[ -r "$alias_file" ]] && source "$alias_file"
    done
    
    # Load functions
    for function_file in "$HOME/.dotfiles/scripts/functions"/*.sh; do
        [[ -r "$function_file" ]] && source "$function_file"
    done
    
    # Enhanced shell environment ready
fi
EOF
        success "Added dotfiles integration to $shell_config"
    else
        log "Shell integration already configured"
    fi
}

# SSH setup wrapper
setup_ssh() {
    # Use consolidated SSH management system
    if [[ -f "$DOTFILES_DIR/scripts/security/ssh.sh" ]]; then
        source "$DOTFILES_DIR/scripts/security/ssh.sh"
        setup_ssh_with_wsl_integration
    else
        warn "SSH setup script not found"
    fi
}

# WSL setup wrapper
setup_wsl() {
    [[ "$IS_WSL" != true ]] && return
    
    log "Configuring WSL integration..."
    
    # Load WSL functions
    if [[ -f "$DOTFILES_DIR/scripts/wsl/core.sh" ]]; then
        source "$DOTFILES_DIR/scripts/wsl/core.sh"
        setup_wsl_aliases
        wsl_log "WSL integration complete"
    else
        warn "WSL integration scripts not found"
    fi
}

# Finalize installation
finalize_installation() {
    log "Finalizing installation..."
    
    # Verify critical installations
    verify_installations
    
    # Set proper permissions
    if [[ -d "$HOME/.ssh" ]]; then
        chmod 700 "$HOME/.ssh"
        chmod 600 "$HOME/.ssh"/* 2>/dev/null || true
    fi
    
    # Clean up any temporary files
    cleanup_temp_files
}

# Verify critical installations
verify_installations() {
    local critical_commands=("git" "curl" "wget")
    
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            warn "Critical command not found: $cmd"
        fi
    done
}

# Cleanup temporary files
cleanup_temp_files() {
    # Remove any temporary directories created during installation
    find /tmp -name "dotfiles-*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
}

# Show next steps to user
show_next_steps() {
    echo
    success "Installation completed! 🎉"
    echo
    echo "Next steps:"
    echo "1. Restart your shell or run: source ~/.bashrc"
    echo "2. Configure Git with your details (if not already done)"
    echo "3. Review the alias cheat sheet: cat ~/.dotfiles/docs/aliases.md"
    
    if is_wsl; then
        echo "4. WSL-specific features are now available (win-ssh, sync-ssh, etc.)"
    fi
    
    if [[ "$INSTALL_AI" == true ]]; then
        echo "5. AI tools installed! Authenticate Claude Code with: claude --auth"
        echo "   AI prompts available at: ~/.claude/"
    fi
    
    echo
    echo "Backup created at: $BACKUP_DIR"
    echo "Dotfiles repository: $DOTFILES_DIR"
}