#!/bin/bash
# Install Poetry (Python dependency manager)
# Uses official installer with user-local target

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing Poetry (Python dependency manager)..."

# Check if Poetry is already installed
if command -v poetry >/dev/null 2>&1; then
    log "Poetry is already installed"
    poetry --version
    exit 0
fi

# Install using official installer, targeting ~/.local
mkdir -p "$HOME/.local/bin"
curl -sSL https://install.python-poetry.org | \
    env POETRY_HOME="$HOME/.local" python3 -

# Configure Poetry to create venvs in-project (.venv/)
if command -v poetry >/dev/null 2>&1; then
    poetry config virtualenvs.in-project true
    success "Poetry installed successfully!"
    poetry --version
else
    error "Poetry installation failed"
    exit 1
fi
