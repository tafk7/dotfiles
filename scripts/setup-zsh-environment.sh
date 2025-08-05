#!/bin/bash
# Optional Zsh environment setup (Oh My Zsh, themes, plugins)
# Separated from core package installation for simplicity

set -euo pipefail

# Source core utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core.sh"

# Install Oh My Zsh if not present
install_oh_my_zsh() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        log "Oh My Zsh already installed"
        return 0
    fi
    
    log "Installing Oh My Zsh..."
    if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
        success "Oh My Zsh installed"
    else
        error "Oh My Zsh installation failed"
        return 1
    fi
}

# Install Powerlevel10k theme
install_powerlevel10k() {
    local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    
    if [[ -d "$theme_dir" ]]; then
        log "Powerlevel10k already installed"
        return 0
    fi
    
    log "Installing Powerlevel10k theme..."
    if git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"; then
        success "Powerlevel10k installed"
    else
        error "Powerlevel10k installation failed"
        return 1
    fi
}

# Install Zsh plugins
install_zsh_plugins() {
    local plugins=(
        "zsh-users/zsh-autosuggestions"
        "zsh-users/zsh-syntax-highlighting"
        "zsh-users/zsh-completions"
    )
    
    for plugin_repo in "${plugins[@]}"; do
        local plugin_name="${plugin_repo##*/}"
        local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin_name"
        
        if [[ -d "$plugin_dir" ]]; then
            log "$plugin_name already installed"
            continue
        fi
        
        log "Installing $plugin_name..."
        if git clone --depth=1 "https://github.com/$plugin_repo.git" "$plugin_dir"; then
            success "$plugin_name installed"
        else
            warn "$plugin_name installation failed"
        fi
    done
}

# Main setup
main() {
    log "Setting up Zsh environment..."
    
    # Ensure zsh is installed
    if ! command -v zsh >/dev/null 2>&1; then
        error "Zsh not installed. Run package installation first."
        exit 1
    fi
    
    install_oh_my_zsh
    install_powerlevel10k
    install_zsh_plugins
    
    success "Zsh environment setup complete"
    log "Restart your shell to see changes"
}

main "$@"