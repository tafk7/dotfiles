#!/bin/bash
# Install lazygit (Terminal UI for git)
# Downloads latest release from GitHub

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing lazygit (Terminal UI for git)..."

LAZYGIT_VERSION=$(github_latest_version "jesseduffield/lazygit" --strip-v)
log "Latest version: v${LAZYGIT_VERSION}"

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary lazygit; then
    CURRENT=$(lazygit --version | grep -oP 'version=\K[^,]+' || echo "0.0.0")
    if [[ "$CURRENT" == "$LAZYGIT_VERSION" ]]; then
        log "lazygit v$CURRENT already installed and up to date"
        exit 0
    fi
    log "lazygit v$CURRENT installed, updating to v$LAZYGIT_VERSION..."
elif command -v lazygit >/dev/null 2>&1; then
    warn "Existing lazygit binary is broken — reinstalling"
fi

ARCH=$(get_arch)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

# lazygit uses "x86_64" for amd64, "arm64" for aarch64
DOWNLOAD_ARCH="$ARCH"
[[ "$ARCH" == "aarch64" ]] && DOWNLOAD_ARCH="arm64"

log "Downloading lazygit v${LAZYGIT_VERSION}..."
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${DOWNLOAD_ARCH}.tar.gz"

tar xf lazygit.tar.gz lazygit

mkdir -p "$HOME/.local/bin"
install lazygit -D -t "$HOME/.local/bin/"

if verify_binary lazygit; then
    success "lazygit installed successfully!"
    lazygit --version
else
    error "lazygit installation failed"
    exit 1
fi
