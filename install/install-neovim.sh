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

# Download the latest AppImage
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/v${LATEST_VERSION}/nvim.appimage"
log "Downloading Neovim v${LATEST_VERSION}..."
curl -L -o nvim.appimage "$DOWNLOAD_URL"

# Make it executable
chmod +x nvim.appimage

# Extract the AppImage (some systems need this for compatibility)
# Try to run directly first, if that fails, extract
if ./nvim.appimage --version >/dev/null 2>&1; then
    log "AppImage works directly, installing..."
    safe_sudo mv nvim.appimage /usr/local/bin/nvim
else
    log "Extracting AppImage for compatibility..."
    ./nvim.appimage --appimage-extract >/dev/null 2>&1

    # Move extracted files to /usr/local
    safe_sudo mv squashfs-root /usr/local/nvim
    safe_sudo ln -sf /usr/local/nvim/AppRun /usr/local/bin/nvim
fi

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
