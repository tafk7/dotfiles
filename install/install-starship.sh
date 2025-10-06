#!/bin/bash

# Install Starship prompt

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Starship prompt..."

# Check if starship is already installed and get version
if command -v starship >/dev/null 2>&1; then
    CURRENT_VERSION=$(starship --version | head -n1 | awk '{print $2}')
    log "Starship $CURRENT_VERSION is already installed"

    # Check for latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/starship/starship/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already up to date!"
        exit 0
    else
        log "Latest version available: $LATEST_VERSION"
        log "Updating Starship..."
    fi
fi

# Install starship using the official installer
log "Downloading and installing Starship..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download and run installer (will install to /usr/local/bin)
curl -sS https://starship.rs/install.sh > install.sh
chmod +x install.sh

# Run installer with automatic yes and explicit bin directory (requires sudo)
log "Installing Starship to /usr/local/bin (requires sudo)..."
safe_sudo sh install.sh --yes --bin-dir /usr/local/bin

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Create config directory
mkdir -p ~/.config

# Link starship configuration
log "Setting up Starship configuration..."
ln -sf "$DOTFILES_DIR/configs/starship.toml" ~/.config/starship.toml

# Verify installation
if command -v starship >/dev/null 2>&1; then
    success "Starship installed successfully!"
    starship --version
else
    error "Starship installation failed"
    exit 1
fi

success "Starship configuration complete!"
log "The dotfiles zsh configuration already uses Starship by default"
log "Just reload your shell to see the new prompt: exec zsh"