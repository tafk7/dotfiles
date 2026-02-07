#!/bin/bash
# Install Starship prompt

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing Starship prompt..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary starship; then
    CURRENT_VERSION=$(starship --version | head -n1 | awk '{print $2}')
    LATEST_VERSION=$(github_latest_version "starship/starship" --strip-v)

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "Starship v$CURRENT_VERSION already up to date!"
        exit 0
    fi
    log "Starship v$CURRENT_VERSION installed, updating to v$LATEST_VERSION..."
elif command -v starship >/dev/null 2>&1; then
    warn "Existing starship binary is broken — reinstalling"
fi

# Install using official installer
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading and installing Starship..."
curl -sS https://starship.rs/install.sh > install.sh
chmod +x install.sh

mkdir -p "$HOME/.local/bin"
sh install.sh --yes --bin-dir "$HOME/.local/bin"

# Link starship configuration
mkdir -p ~/.config
ln -sf "$DOTFILES_DIR/configs/starship.toml" ~/.config/starship.toml

if verify_binary starship; then
    success "Starship installed successfully!"
    starship --version
else
    error "Starship installation failed"
    exit 1
fi
