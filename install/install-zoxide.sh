#!/bin/bash
# Install zoxide (smart directory jumper)
# Uses official installer with basic verification

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing zoxide (smart directory jumper)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary zoxide; then
    CURRENT_VERSION=$(zoxide --version | awk '{print $2}')
    LATEST_VERSION=$(github_latest_version "ajeetdsouza/zoxide" --strip-v)

    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
        success "zoxide v$CURRENT_VERSION already up to date!"
        exit 0
    fi
    log "zoxide v$CURRENT_VERSION installed, updating to v$LATEST_VERSION..."
elif command -v zoxide >/dev/null 2>&1; then
    warn "Existing zoxide binary is broken — reinstalling"
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading zoxide installer..."
curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o install.sh

if [[ ! -s install.sh ]] || ! grep -q "zoxide" install.sh; then
    error "Downloaded installer is invalid"
    exit 1
fi

mkdir -p "$HOME/.local/bin"

log "Running zoxide installer (installing to ~/.local/bin)..."
chmod +x install.sh
./install.sh --bin-dir="$HOME/.local/bin"

if verify_binary zoxide; then
    success "zoxide installed successfully!"
    zoxide --version
else
    error "zoxide installation failed"
    exit 1
fi
