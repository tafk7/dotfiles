#!/bin/bash

# Install Claude Code CLI

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Claude Code CLI..."

# Check if Node.js is available
if ! command -v node >/dev/null 2>&1; then
    error "Node.js is required but not found"
    error "Please install Node.js first (NVM is installed with --work flag)"
    exit 1
fi

# Check Node.js version (requires 18+)
NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [[ "$NODE_VERSION" -lt 18 ]]; then
    error "Node.js 18 or higher is required (current: $(node -v))"
    error "Please upgrade Node.js using: nvm install --lts"
    exit 1
fi

# Check if npm is available
if ! command -v npm >/dev/null 2>&1; then
    error "npm is required but not found"
    exit 1
fi

# Check if Claude Code is already installed and get version
if command -v claude >/dev/null 2>&1; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "unknown")
    log "Claude Code $CURRENT_VERSION is already installed"

    # Check for latest version from npm
    LATEST_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "unknown")

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Already up to date!"
        exit 0
    else
        log "Latest version available: $LATEST_VERSION"
        log "Updating Claude Code..."
    fi
fi

# Install or update Claude Code using npm
log "Installing Claude Code via npm..."

# Use npm install without sudo (works with NVM)
if npm install -g @anthropic-ai/claude-code; then
    success "Claude Code installed successfully!"
else
    error "Claude Code installation failed"
    error "Try running: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

# Verify installation
if command -v claude >/dev/null 2>&1; then
    INSTALLED_VERSION=$(claude --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -n1 || echo "installed")
    success "Claude Code $INSTALLED_VERSION is ready!"

    # Run claude doctor to verify setup
    log "Running diagnostics..."
    if claude doctor >/dev/null 2>&1; then
        success "Claude Code passed all diagnostic checks"
    else
        warn "Claude Code installed but diagnostics reported issues"
        warn "Run 'claude doctor' for details"
    fi
else
    error "Claude Code installation verification failed"
    exit 1
fi

# Show helpful information
echo ""
log "Claude Code is installed and ready to use!"
log "Available shortcuts:"
log "  cl    - Start new Claude session"
log "  clc   - Continue last Claude session"
log "  clp   - One-off command (non-interactive)"
echo ""
log "To authenticate, run: claude"
log "To verify installation: claude doctor"
