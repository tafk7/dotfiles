#!/bin/bash
# Install zoxide (smart directory jumper)
# Uses official installer with basic verification

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing zoxide (smart directory jumper)..."

# Check if zoxide is already installed and get version
if command -v zoxide >/dev/null 2>&1; then
    CURRENT_VERSION=$(zoxide --version | awk '{print $2}')
    log "zoxide $CURRENT_VERSION is already installed"

    # Check for latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already up to date!"
        exit 0
    else
        log "Latest version available: $LATEST_VERSION"
        log "Updating zoxide..."
    fi
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download installer
log "Downloading zoxide installer..."
curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o install.sh

# Verify we got a script (enhanced validation)
if [[ ! -s install.sh ]]; then
    error "Downloaded installer is empty"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check file size (installer should be at least 1KB)
INSTALLER_SIZE=$(stat -c%s install.sh 2>/dev/null || stat -f%z install.sh 2>/dev/null)
if [[ $INSTALLER_SIZE -lt 1024 ]]; then
    error "Downloaded installer is too small ($INSTALLER_SIZE bytes)"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Verify content
if ! grep -q "zoxide" install.sh; then
    error "Downloaded installer does not appear to be for zoxide"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Run installer with explicit /usr/local/bin directory
log "Running zoxide installer (installing to /usr/local/bin)..."
chmod +x install.sh

# Install to /usr/local/bin for system-wide access
if ! ./install.sh --bin-dir=/usr/local/bin; then
    error "Installer failed. You may need sudo permissions for /usr/local/bin"
    log "Try running: sudo ./install.sh --bin-dir=/usr/local/bin"
    cd -
    rm -rf "$TEMP_DIR"
    exit 1
fi

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