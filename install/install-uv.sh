#!/bin/bash
# Install uv (fast Python package manager)
# Uses official installer with user-local target

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing uv (fast Python package manager)..."

# Check if uv is already installed
if command -v uv >/dev/null 2>&1; then
    log "uv is already installed"
    uv --version
    exit 0
fi

# Install using official installer, targeting ~/.local/bin
mkdir -p "$HOME/.local/bin"
curl -LsSf https://astral.sh/uv/install.sh | \
    env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh

# Verify installation
if command -v uv >/dev/null 2>&1; then
    success "uv installed successfully!"
    uv --version
else
    error "uv installation failed"
    exit 1
fi
