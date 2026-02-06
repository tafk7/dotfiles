#!/bin/bash
# Install Claude Code CLI (native installer)
set -euo pipefail
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Claude Code CLI..."

# Check if already installed and show version
if command -v claude >/dev/null 2>&1; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | head -1 || echo "unknown")
    log "Claude Code already installed: $CURRENT_VERSION"
    log "Updating..."
fi

# Install/update via native installer
if curl -fsSL https://cli.claude.ai/install.sh | sh; then
    success "Claude Code installed successfully!"
else
    error "Claude Code installation failed"
    exit 1
fi

# Verify
if command -v claude >/dev/null 2>&1; then
    INSTALLED_VERSION=$(claude --version 2>/dev/null | head -1 || echo "installed")
    success "Claude Code $INSTALLED_VERSION is ready!"
else
    error "Claude Code installation verification failed"
    exit 1
fi

# Shortcuts and next steps
echo ""
log "Available shortcuts:"
log "  cl    - Start new Claude session"
log "  clc   - Continue last Claude session"
log "  clp   - One-off command (non-interactive)"
echo ""
log "Next steps:"
log "  1. Run 'claude' to authenticate"
log "  2. Run 'update-claude-commands' to sync slash commands"
