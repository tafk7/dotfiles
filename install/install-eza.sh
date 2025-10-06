#!/bin/bash
# Install eza (modern ls replacement)
# Direct binary installation from GitHub releases

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing eza (modern ls replacement)..."

# Check if eza is already installed
if command -v eza >/dev/null 2>&1; then
    log "eza is already installed"
    eza --version
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Get latest version from GitHub
log "Fetching latest eza release..."
EZA_VERSION=$(curl -s "https://api.github.com/repos/eza-community/eza/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')

if [[ -z "$EZA_VERSION" ]]; then
    error "Could not determine latest eza version"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Download binary
log "Downloading eza v${EZA_VERSION}..."
curl -Lo eza.tar.gz "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_x86_64-unknown-linux-gnu.tar.gz"

# Extract and install
tar xf eza.tar.gz
safe_sudo install -D ./eza -t /usr/local/bin/

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v eza >/dev/null 2>&1; then
    success "eza installed successfully!"
    eza --version
else
    error "eza installation failed"
    exit 1
fi
