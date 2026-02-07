#!/bin/bash
# Install git-delta (syntax-highlighted diffs)
# Direct binary installation from GitHub releases

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing git-delta (syntax-highlighted diffs)..."

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary delta; then
    log "delta is already installed"
    delta --version
    exit 0
elif command -v delta >/dev/null 2>&1; then
    warn "Existing delta binary is broken — reinstalling"
fi

ARCH=$(get_arch)
# delta tags have NO v prefix
DELTA_VERSION=$(github_latest_version "dandavison/delta")
log "Latest version: ${DELTA_VERSION}"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading delta ${DELTA_VERSION}..."
curl -Lo delta.tar.gz "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${ARCH}-unknown-linux-gnu.tar.gz"

tar xf delta.tar.gz
mkdir -p "$HOME/.local/bin"
install -D "./delta-${DELTA_VERSION}-${ARCH}-unknown-linux-gnu/delta" "$HOME/.local/bin/delta"

if verify_binary delta; then
    success "delta installed successfully!"
    delta --version
else
    error "delta installation failed"
    exit 1
fi
