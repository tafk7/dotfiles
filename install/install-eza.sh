#!/bin/bash
# Install eza (modern ls replacement)
# Direct binary installation from GitHub releases

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing eza (modern ls replacement)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary eza; then
    log "eza is already installed"
    eza --version
    exit 0
elif command -v eza >/dev/null 2>&1; then
    warn "Existing eza binary is broken — reinstalling"
fi

ARCH=$(get_arch)
EZA_VERSION=$(github_latest_version "eza-community/eza" --strip-v)
log "Latest version: v${EZA_VERSION}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading eza v${EZA_VERSION}..."
curl -Lo eza.tar.gz "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${ARCH}-unknown-linux-gnu.tar.gz"

tar xf eza.tar.gz
mkdir -p "$HOME/.local/bin"
install -D ./eza -t "$HOME/.local/bin/"

if verify_binary eza; then
    success "eza installed successfully!"
    eza --version
else
    error "eza installation failed"
    exit 1
fi
