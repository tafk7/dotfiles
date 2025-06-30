#!/bin/bash
# Work setup script - Professional development tools
# This file is sourced by install.sh when --work flag is used

# Main work package installation function
install_work_packages() {
    log "Installing work packages..."
    
    # Install Microsoft tools (Azure CLI, VS Code)
    install_microsoft_tools
    
    # Install Node.js development tools
    install_nodejs_tools
    
    # Install Python development tools
    install_python_tools
    
    # Install VS Code extensions
    install_work_vscode_extensions
    
    success "Work environment configured"
}

# Install Microsoft development tools
install_microsoft_tools() {
    log "Installing Microsoft development tools..."
    
    # Source Microsoft integration functions
    if [[ -f "$DOTFILES_DIR/scripts/install/microsoft.sh" ]]; then
        source "$DOTFILES_DIR/scripts/install/microsoft.sh"
        
        # Clean up any broken Microsoft repositories first
        cleanup_microsoft_repos
        
        # Install Azure CLI
        if install_azure_cli_microsoft; then
            success "Azure CLI installed - login with: az login"
        else
            warn "Azure CLI installation failed"
        fi
        
        # Install VS Code
        if install_vscode_microsoft; then
            success "VS Code installed"
        else
            warn "VS Code installation failed"
        fi
    else
        warn "Microsoft integration not found, skipping Azure CLI and VS Code"
    fi
}

# Install Node.js development tools
install_nodejs_tools() {
    log "Installing Node.js development tools..."
    
    local npm_packages=("yarn" "typescript" "eslint" "prettier" "nodemon")
    install_npm_packages "${npm_packages[@]}"
}

# Install Python development tools
install_python_tools() {
    if ! command -v pip3 >/dev/null 2>&1; then
        warn "pip3 not found - skipping Python tools installation"
        return 1
    fi
    
    log "Installing Python development tools..."
    
    local python_packages=("black" "flake8" "mypy" "pylint")
    for pkg in "${python_packages[@]}"; do
        install_python_package "$pkg" "Python $pkg"
    done
    
    success "Python development tools installed"
}

# Install VS Code extensions for work
install_work_vscode_extensions() {
    log "Installing VS Code extensions for work..."
    
    local extensions=(
        "ms-vscode-remote.remote-wsl"
        "ms-python.python"
        "esbenp.prettier-vscode"
        "ms-azuretools.vscode-docker"
        "ms-vscode.vscode-typescript-next"
        "bradlc.vscode-tailwindcss"
    )
    
    install_vscode_extensions "${extensions[@]}"
}
