#!/bin/bash

# Install Starship prompt

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

log "Installing Starship prompt..."

# Check if starship is already installed
if command -v starship >/dev/null 2>&1; then
    log "Starship is already installed"
    starship --version
    exit 0
fi

# Install starship using the official installer
log "Downloading and installing Starship..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download and run installer (will install to /usr/local/bin)
curl -sS https://starship.rs/install.sh > install.sh
chmod +x install.sh

# Run installer with automatic yes (requires sudo)
log "Installing Starship (requires sudo)..."
sudo sh install.sh --yes

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

log_success "Starship configuration complete!"
log_info "The dotfiles zsh configuration already uses Starship by default"
log_info "Just reload your shell to see the new prompt: exec zsh"