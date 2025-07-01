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
    cleanup_broken_repos
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

# Clean up broken repositories from previous runs
cleanup_broken_repos() {
    log "Checking for broken repositories..."
    
    # Check if Microsoft integration is available and clean up if needed
    if [[ -f "$DOTFILES_DIR/scripts/install/microsoft.sh" ]]; then
        source "$DOTFILES_DIR/scripts/install/microsoft.sh"
        
        # Check if Microsoft repos exist and are causing issues
        if [[ -f /etc/apt/sources.list.d/azure-cli.list ]] || [[ -f /etc/apt/sources.list.d/vscode.list ]]; then
            # Test if apt update would fail due to Microsoft repos
            if ! safe_sudo apt-get update >/dev/null 2>&1; then
                log "Found broken Microsoft repositories, cleaning up..."
                cleanup_microsoft_repos
            else
                log "Microsoft repositories are working correctly"
            fi
        fi
    fi
    
    log "Repository cleanup completed"
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
    echo "=== Next Steps ==="
    echo
    
    # Basic steps (always shown)
    echo "1. Restart your shell or run: source ~/.bashrc"
    echo "2. Review available aliases and functions: alias | less"
    
    # Git configuration check
    if ! git config --global user.name >/dev/null 2>&1; then
        echo "3. Configure Git with your information:"
        echo "   git config --global user.name \"Your Name\""
        echo "   git config --global user.email \"your.email@example.com\""
    fi
    
    # Zsh/Powerlevel10k setup (zsh is now installed by default)
    if [[ -f "$HOME/.zshrc" ]]; then
        echo
        echo "=== Zsh Shell Configuration ==="
        
        # Check if zsh is the default shell
        if [[ "$SHELL" != "$(which zsh)" ]]; then
            echo "• Make Zsh your default shell: chsh -s \$(which zsh)"
            echo "  (You'll need to log out and back in for this to take effect)"
        fi
        
        if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
            echo "• Install Oh My Zsh: sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        fi
        
        if [[ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
            echo "• Install Powerlevel10k theme:"
            echo "  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k"
        fi
        
        if [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]] && [[ ! -f "$HOME/.p10k.zsh" ]]; then
            echo "• Configure Powerlevel10k: p10k configure"
        fi
        
        if [[ -d "$HOME/.oh-my-zsh" ]] && [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]] && [[ -f "$HOME/.p10k.zsh" ]]; then
            echo "• Zsh with Powerlevel10k is fully configured! 🚀"
        fi
    fi
    
    # Work-specific steps
    if [[ "$INSTALL_WORK" == true ]]; then
        echo
        echo "=== Work Tools Installed ==="
        if command -v az >/dev/null 2>&1; then
            echo "• Azure CLI: Login with 'az login'"
        fi
        if ! is_wsl && command -v code >/dev/null 2>&1; then
            echo "• VS Code: Launch with 'code .'"
            echo "  Extensions installed: Python, Prettier, Docker, TypeScript, Tailwind"
        fi
        echo "• Node.js tools: yarn, typescript, eslint, prettier, nodemon"
        echo "• Python tools: black, flake8, mypy, pylint"
        if command -v npm >/dev/null 2>&1; then
            echo "• NPM global packages installed in: ~/.npm-global"
        fi
    fi
    
    # Personal-specific steps
    if [[ "$INSTALL_PERSONAL" == true ]]; then
        echo
        echo "=== Personal Tools Installed ==="
        echo "• Media tools: ffmpeg available for video/audio processing"
    fi
    
    # AI-specific steps
    if [[ "$INSTALL_AI" == true ]]; then
        echo
        echo "=== AI Tools Installed ==="
        echo "• Claude Code: Authenticate with 'claude --auth'"
        echo "• AI prompts available at: ~/.claude/"
        echo "• Start coding with AI: 'claude' in any project directory"
    fi
    
    # WSL-specific features
    if is_wsl; then
        echo
        echo "=== WSL Features Available ==="
        echo "• Import SSH keys from Windows: sync-ssh"
        echo "• Clipboard integration: pbcopy/pbpaste aliases"
        if [[ "$INSTALL_WORK" == true ]]; then
            echo "• VS Code: Use from Windows with Remote-WSL extension"
        fi
    fi
    
    # Helpful commands
    echo
    echo "=== Helpful Commands ==="
    echo "• View all aliases: alias"
    echo "• Reload shell config: reload"
    echo "• Search processes: psg <name>"
    echo "• View markdown files: md <file>"
    
    # Installation info
    echo
    echo "=== Installation Info ==="
    echo "• Backup created at: $BACKUP_DIR"
    echo "• Dotfiles location: $DOTFILES_DIR"
    if [[ -f "$STATE_FILE" ]]; then
        echo "• Installation log: $STATE_FILE"
    fi
}