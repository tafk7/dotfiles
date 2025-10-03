#!/bin/bash
# Install eza (modern ls replacement)
# Fetches latest version from GitHub

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

# Get latest release URL from GitHub API
log "Fetching latest eza release..."
LATEST_URL=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest \
    | grep "browser_download_url.*_amd64.deb" \
    | cut -d '"' -f 4)

if [[ -z "$LATEST_URL" ]]; then
    error "Could not find latest eza release"
    exit 1
fi

# Download to temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

log "Downloading eza from: $LATEST_URL"
wget -q "$LATEST_URL" -O eza.deb

# Install the package
log "Installing eza (requires sudo)..."
if safe_sudo dpkg -i eza.deb; then
    success "eza installed successfully!"
else
    # Try to fix dependencies if dpkg failed
    warn "Fixing dependencies..."
    safe_sudo apt-get install -f -y
fi

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v eza >/dev/null 2>&1; then
    success "eza installation complete!"
    eza --version
else
    error "eza installation failed"
    exit 1
fi