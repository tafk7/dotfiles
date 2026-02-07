#!/bin/bash
# Install glow (terminal Markdown renderer)

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing glow (terminal Markdown renderer)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary glow; then
    log "glow is already installed"
    glow --version
    exit 0
elif command -v glow >/dev/null 2>&1; then
    warn "Existing glow binary is broken — reinstalling"
fi

ARCH=$(get_arch)
# glow uses "arm64" not "aarch64"
[[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

GLOW_VERSION=$(github_latest_version "charmbracelet/glow" --strip-v)
log "Latest version: v${GLOW_VERSION}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading glow v${GLOW_VERSION}..."
curl -Lo glow.tar.gz "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_${ARCH}.tar.gz"

tar xf glow.tar.gz
mkdir -p "$HOME/.local/bin"
install -D "glow_${GLOW_VERSION}_Linux_${ARCH}/glow" -t "$HOME/.local/bin/"

if verify_binary glow; then
    success "glow installed successfully!"
    glow --version
else
    error "glow installation failed"
    exit 1
fi
