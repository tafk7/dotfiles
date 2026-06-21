#!/bin/bash
# Install Poetry (Python dependency manager)
# Uses official installer with user-local target

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

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

# Install into a dedicated POETRY_HOME (not the user's general ~/.local) so the
# tree can be removed cleanly on uninstall, then symlink the launcher onto PATH.
# Download the installer to a file first rather than piping the network to python.
export POETRY_HOME="$HOME/.local/share/pypoetry"
mkdir -p "$HOME/.local/bin"

log "Downloading Poetry installer (install.python-poetry.org)..."
poetry_installer="$(mktemp)"
curl -fsSL https://install.python-poetry.org -o "$poetry_installer"
log "Running Poetry installer from $poetry_installer"
python3 "$poetry_installer"
rm -f "$poetry_installer"

# The installer places the launcher at $POETRY_HOME/bin/poetry, which is not on
# PATH; link it into ~/.local/bin (which is).
ln -sf "$POETRY_HOME/bin/poetry" "$HOME/.local/bin/poetry"

if verify_binary poetry; then
    poetry config virtualenvs.in-project true
    success "Poetry installed successfully!"
    poetry --version
else
    error "Poetry installation failed"
    exit 1
fi
