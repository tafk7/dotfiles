#!/bin/bash
# Install eza (modern ls replacement)
# Tries APT repository first, falls back to binary installation

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

# Method 1: Try official APT repository (preferred for updates)
log "Attempting to install from APT repository..."

# Ensure gpg is installed
if ! command -v gpg >/dev/null 2>&1; then
    log "Installing gpg..."
    safe_sudo apt-get update
    safe_sudo apt-get install -y gpg
fi

# Add eza repository
safe_sudo mkdir -p /etc/apt/keyrings
if wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | safe_sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg 2>/dev/null; then
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | safe_sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    safe_sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

    # Try to install from repository
    if safe_sudo apt-get update 2>/dev/null && safe_sudo apt-get install -y eza 2>/dev/null; then
        success "eza installed from APT repository!"
        eza --version
        exit 0
    else
        warn "APT repository installation failed, trying direct binary download..."
    fi
else
    warn "Could not set up APT repository, trying direct binary download..."
fi

# Method 2: Direct binary installation from GitHub
log "Installing eza binary from GitHub..."

# Get latest version
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

log "Fetching latest eza release..."
EZA_VERSION=$(curl -s "https://api.github.com/repos/eza-community/eza/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')

if [[ -z "$EZA_VERSION" ]]; then
    error "Could not determine latest eza version"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

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