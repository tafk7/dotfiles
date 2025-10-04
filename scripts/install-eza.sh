#!/bin/bash
# Install eza (modern ls replacement)
# Uses official APT repository for reliable updates

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

log "Installing eza (modern ls replacement)..."

# Check if eza is already installed
if command -v eza >/dev/null 2>&1; then
    log "eza is already installed"
    eza --version
    exit 0
fi

# Method 1: Use official APT repository (recommended)
log "Setting up eza repository..."

# Ensure gpg is installed
if ! command -v gpg >/dev/null 2>&1; then
    log "Installing gpg..."
    safe_sudo apt-get update
    safe_sudo apt-get install -y gpg
fi

# Add eza repository
safe_sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | safe_sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | safe_sudo tee /etc/apt/sources.list.d/gierens.list
safe_sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

# Update and install
log "Installing eza from repository..."
safe_sudo apt-get update
safe_sudo apt-get install -y eza

# Verify installation
if command -v eza >/dev/null 2>&1; then
    success "eza installation complete!"
    eza --version
else
    error "eza installation failed"
    exit 1
fi