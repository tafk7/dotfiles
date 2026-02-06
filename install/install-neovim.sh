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

# Remove old installation if it exists (user-local)
if [[ -d "$HOME/.local/nvim" ]]; then
    log "Removing old Neovim installation..."
    rm -rf "$HOME/.local/nvim"
fi

# Also clean up legacy system-wide installation if present
if [[ -d "/opt/nvim-linux-x86_64" ]]; then
    log "Found legacy system-wide Neovim in /opt, skipping removal (may need manual cleanup)"
fi

# Extract to ~/.local/nvim
log "Extracting Neovim to ~/.local/nvim..."
mkdir -p "$HOME/.local"
tar -C "$HOME/.local" -xzf nvim-linux-x86_64.tar.gz
mv "$HOME/.local/nvim-linux-x86_64" "$HOME/.local/nvim"

# Create symlink to ~/.local/bin
log "Creating symlink in ~/.local/bin..."
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"

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
