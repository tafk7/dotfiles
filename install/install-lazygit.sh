#!/bin/bash
# Install lazygit (Terminal UI for git)
# Downloads latest release from GitHub

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing lazygit (Terminal UI for git)..."

# Initialize version variable
LAZYGIT_VERSION=""

# Check if lazygit is already installed and compare versions
if command -v lazygit >/dev/null 2>&1; then
    CURRENT_VERSION=$(lazygit --version | grep -oP 'version=\K[^,]+' || echo "0.0.0")
    log "Checking for updates..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    
    if [[ "$CURRENT_VERSION" == "$LAZYGIT_VERSION" ]]; then
        log "lazygit is already installed and up to date (v$CURRENT_VERSION)"
        exit 0
    else
        log "lazygit v$CURRENT_VERSION is installed, but v$LAZYGIT_VERSION is available"
        log "Updating to latest version..."
    fi
else
    # Not installed, fetch latest version
    log "Fetching latest lazygit release..."
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
fi

if [[ -z "$LAZYGIT_VERSION" ]]; then
    error "Could not determine latest lazygit version"
    exit 1
fi

log "Latest version: v${LAZYGIT_VERSION}"

# Download to temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the binary
log "Downloading lazygit..."
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"

# Extract
tar xf lazygit.tar.gz lazygit

# Install to /usr/local/bin
log "Installing lazygit (requires sudo)..."
safe_sudo install lazygit -D -t /usr/local/bin/

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v lazygit >/dev/null 2>&1; then
    success "lazygit installation complete!"
    lazygit --version
else
    error "lazygit installation failed"
    exit 1
fi