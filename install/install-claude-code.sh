#!/bin/bash
# Install Claude Code CLI (native installer)
set -euo pipefail
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Claude Code CLI..."

# Check existing installation
if verify_binary claude; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    log "Claude Code already installed: $CURRENT_VERSION"
    log "Updating..."
fi

if curl -fsSL https://cli.claude.ai/install.sh | sh; then
    success "Claude Code installed successfully!"
else
    error "Claude Code installation failed"
    exit 1
fi

if verify_binary claude; then
    INSTALLED_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
    success "Claude Code $INSTALLED_VERSION is ready!"
else
    error "Claude Code installation verification failed"
    exit 1
fi
