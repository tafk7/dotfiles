#!/bin/bash
# Install btop (modern resource monitor)
# Direct binary installation from GitHub releases

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing btop (modern resource monitor)..."

# Check if btop is already installed
if command -v btop >/dev/null 2>&1; then
    log "btop is already installed"
    btop --version
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Get latest version from GitHub (tags use v prefix)
log "Fetching latest btop release..."
BTOP_VERSION=$(curl -s "https://api.github.com/repos/aristocratos/btop/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')

if [[ -z "$BTOP_VERSION" ]]; then
    error "Could not determine latest btop version"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Download binary
log "Downloading btop v${BTOP_VERSION}..."
curl -Lo btop.tbz "https://github.com/aristocratos/btop/releases/download/v${BTOP_VERSION}/btop-x86_64-unknown-linux-musl.tbz"

# Extract and find btop binary
tar xjf btop.tbz

# Find the btop binary in extracted contents
BTOP_BIN=$(find . -name "btop" -type f -executable 2>/dev/null | head -1)
if [[ -z "$BTOP_BIN" ]]; then
    # Fallback: look for any btop binary regardless of executable bit
    BTOP_BIN=$(find . -name "btop" -type f 2>/dev/null | head -1)
fi

if [[ -z "$BTOP_BIN" ]]; then
    error "Could not find btop binary in archive"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Install to user-local bin directory
mkdir -p "$HOME/.local/bin"
install -D "$BTOP_BIN" "$HOME/.local/bin/btop"

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v btop >/dev/null 2>&1; then
    success "btop installed successfully!"
    btop --version
else
    error "btop installation failed"
    exit 1
fi
