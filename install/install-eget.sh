#!/bin/bash
# Install eget (GitHub release binary manager)
# Bootstraps eget itself — all other binary tools are then managed via eget.toml

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

EGET_VERSION="1.3.4"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing eget v${EGET_VERSION}..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary eget; then
    CURRENT=$(eget --version 2>&1 | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
    if [[ "$CURRENT" == "$EGET_VERSION" ]]; then
        success "eget v$CURRENT already up to date"
        exit 2
    fi
    log "eget v$CURRENT installed, updating to v$EGET_VERSION..."
elif command -v eget >/dev/null 2>&1; then
    warn "Existing eget binary is broken — reinstalling"
fi

ARCH=$(get_arch)
case "$ARCH" in
    x86_64)  EGET_ARCH="amd64" ;;
    aarch64) EGET_ARCH="arm64" ;;
esac

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading eget v${EGET_VERSION}..."
curl -fLSso eget.tar.gz "https://github.com/zyedidia/eget/releases/download/v${EGET_VERSION}/eget-${EGET_VERSION}-linux_${EGET_ARCH}.tar.gz"

tar xf eget.tar.gz
mkdir -p "$HOME/.local/bin"
install -D "eget-${EGET_VERSION}-linux_${EGET_ARCH}/eget" "$HOME/.local/bin/eget"

if verify_binary eget; then
    success "eget v${EGET_VERSION} installed"
else
    error "eget installation failed"
    exit 1
fi
