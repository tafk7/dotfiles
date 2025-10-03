#!/bin/bash
# Install zoxide (smart directory jumper)
# Uses official installer with basic verification

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

log "Installing zoxide (smart directory jumper)..."

# Check if zoxide is already installed
if command -v zoxide >/dev/null 2>&1; then
    log "zoxide is already installed"
    zoxide --version
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download installer
log "Downloading zoxide installer..."
curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o install.sh

# Verify we got a script (basic check)
if [[ ! -s install.sh ]] || ! grep -q "zoxide" install.sh; then
    error "Downloaded installer appears invalid"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Run installer
log "Running zoxide installer..."
chmod +x install.sh
./install.sh

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v zoxide >/dev/null 2>&1; then
    success "zoxide installed successfully!"
    zoxide --version
    log "Add 'eval \"\$(zoxide init zsh)\"' to your .zshrc to enable"
else
    error "zoxide installation failed"
    exit 1
fi