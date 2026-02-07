#!/bin/bash
# Install Poetry (Python dependency manager)
# Uses official installer with user-local target

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing Poetry (Python dependency manager)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary poetry; then
    log "Poetry is already installed"
    poetry --version
    exit 2
elif command -v poetry >/dev/null 2>&1; then
    warn "Existing poetry binary is broken — reinstalling"
fi

mkdir -p "$HOME/.local/bin"
curl -sSL https://install.python-poetry.org | \
    env POETRY_HOME="$HOME/.local" python3 -

if verify_binary poetry; then
    poetry config virtualenvs.in-project true
    success "Poetry installed successfully!"
    poetry --version
else
    error "Poetry installation failed"
    exit 1
fi
