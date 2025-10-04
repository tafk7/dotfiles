#!/bin/bash
# Install NVM (Node Version Manager) and Node.js
# Best practice for Node.js on WSL/Ubuntu - avoids permission and path issues

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

log "Installing NVM (Node Version Manager)..."

# NVM installation directory
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Check if already installed
if [[ -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log "NVM is already installed at $NVM_DIR"
    # Source NVM to check version
    . "$NVM_DIR/nvm.sh"
    nvm --version
    
    # Check if Node.js is installed via NVM
    if command -v node >/dev/null 2>&1; then
        log "Node.js $(node --version) is already installed via NVM"
        log "npm $(npm --version) is available"
        exit 0
    else
        log "NVM is installed but Node.js is not. Installing Node.js LTS..."
    fi
else
    # Create NVM directory
    mkdir -p "$NVM_DIR"
    
    # Download and install NVM
    log "Downloading NVM installer..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    
    # Verify installation
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        error "NVM installation failed"
        exit 1
    fi
    
    success "NVM installed successfully!"
fi

# Source NVM
log "Loading NVM..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Install latest LTS Node.js
log "Installing latest LTS Node.js..."
nvm install --lts
nvm use --lts
nvm alias default lts/*

# Verify installation
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    success "Node.js $(node --version) and npm $(npm --version) installed via NVM!"
    log "NVM will be automatically loaded in new shell sessions"
    log "To use in current session: source ~/.bashrc (or ~/.zshrc)"
else
    error "Node.js installation via NVM failed"
    exit 1
fi

# Clean up any old npm global directory if it exists
if [[ -d "$HOME/.npm-global" ]] && [[ -z "$(ls -A "$HOME/.npm-global" 2>/dev/null)" ]]; then
    log "Removing empty legacy .npm-global directory..."
    rm -rf "$HOME/.npm-global"
fi