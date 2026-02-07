#!/bin/bash
# Install uv (fast Python package manager)
# Uses official installer with user-local target

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing uv (fast Python package manager)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary uv; then
    log "uv is already installed"
    uv --version
    exit 0
elif command -v uv >/dev/null 2>&1; then
    warn "Existing uv binary is broken — reinstalling"
fi

mkdir -p "$HOME/.local/bin"
curl -LsSf https://astral.sh/uv/install.sh | \
    env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh

if verify_binary uv; then
    success "uv installed successfully!"
    uv --version
else
    error "uv installation failed"
    exit 1
fi
