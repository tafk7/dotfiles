#!/bin/bash
# Install git-delta (syntax-highlighted diffs)
# Direct binary installation from GitHub releases

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing git-delta (syntax-highlighted diffs)..."

# Check if delta is already installed
if command -v delta >/dev/null 2>&1; then
    log "delta is already installed"
    delta --version
    exit 0
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Get latest version from GitHub (tags have NO v prefix)
log "Fetching latest delta release..."
DELTA_VERSION=$(curl -s "https://api.github.com/repos/dandavison/delta/releases/latest" | grep -Po '"tag_name": "\K[^"]*')

if [[ -z "$DELTA_VERSION" ]]; then
    error "Could not determine latest delta version"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Download binary
log "Downloading delta ${DELTA_VERSION}..."
curl -Lo delta.tar.gz "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu.tar.gz"

# Extract and install to user-local bin directory
tar xf delta.tar.gz
mkdir -p "$HOME/.local/bin"
install -D "./delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu/delta" "$HOME/.local/bin/delta"

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v delta >/dev/null 2>&1; then
    success "delta installed successfully!"
    delta --version
else
    error "delta installation failed"
    exit 1
fi
