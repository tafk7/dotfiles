#!/bin/bash

# Install latest stable Neovim from GitHub releases

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Neovim..."

# Check if neovim is already installed and get version
if command -v nvim >/dev/null 2>&1; then
    CURRENT_VERSION=$(nvim --version | head -n1 | awk '{print $2}' | sed 's/^v//')
    log "Neovim $CURRENT_VERSION is already installed"

    # Check for latest stable version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already up to date!"
        exit 0
    else
        log "Latest version available: $LATEST_VERSION"
        log "Updating Neovim..."
    fi
fi

# Get latest stable release version
log "Fetching latest Neovim release..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/neovim/neovim/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [[ -z "$LATEST_VERSION" ]]; then
    error "Failed to fetch latest version"
    exit 1
fi

log "Latest stable version: $LATEST_VERSION"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the latest prebuilt tarball (official method from GitHub releases)
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/v${LATEST_VERSION}/nvim-linux-x86_64.tar.gz"
log "Downloading Neovim v${LATEST_VERSION}..."
curl -LO "$DOWNLOAD_URL"

# Verify download succeeded
if [[ ! -f "nvim-linux-x86_64.tar.gz" ]]; then
    error "Download failed"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Remove old installation if it exists
if [[ -d "/opt/nvim-linux-x86_64" ]]; then
    log "Removing old Neovim installation..."
    safe_sudo rm -rf /opt/nvim-linux-x86_64
fi

# Extract to /opt
log "Extracting Neovim to /opt..."
safe_sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz

# Create symlink to /usr/local/bin
log "Creating symlink in /usr/local/bin..."
safe_sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim

# Cleanup
cd -
rm -rf "$TEMP_DIR"

# Verify installation
if command -v nvim >/dev/null 2>&1; then
    success "Neovim installed successfully!"
    nvim --version | head -n 1
else
    error "Neovim installation failed"
    exit 1
fi

success "Neovim installation complete!"
log "Run 'nvim' to start Neovim"
