#!/bin/bash
# Install btop (modern resource monitor)
# Direct binary installation from GitHub releases

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing btop (modern resource monitor)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary btop; then
    log "btop is already installed"
    btop --version
    exit 0
elif command -v btop >/dev/null 2>&1; then
    warn "Existing btop binary is broken — reinstalling"
fi

ARCH=$(get_arch)
BTOP_VERSION=$(github_latest_version "aristocratos/btop" --strip-v)
log "Latest version: v${BTOP_VERSION}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

# btop uses musl static builds (works on any glibc)
log "Downloading btop v${BTOP_VERSION}..."
curl -Lo btop.tbz "https://github.com/aristocratos/btop/releases/download/v${BTOP_VERSION}/btop-${ARCH}-unknown-linux-musl.tbz"

tar xjf btop.tbz

# Find the btop binary in extracted contents
BTOP_BIN=$(find . -name "btop" -type f -executable 2>/dev/null | head -1)
if [[ -z "$BTOP_BIN" ]]; then
    BTOP_BIN=$(find . -name "btop" -type f 2>/dev/null | head -1)
fi

if [[ -z "$BTOP_BIN" ]]; then
    error "Could not find btop binary in archive"
    exit 1
fi

mkdir -p "$HOME/.local/bin"
install -D "$BTOP_BIN" "$HOME/.local/bin/btop"

if verify_binary btop; then
    success "btop installed successfully!"
    btop --version
else
    error "btop installation failed"
    exit 1
fi
