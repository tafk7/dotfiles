#!/bin/bash
# Install Neovim from GitHub releases
# glibc >= 2.32: latest release
# glibc <  2.32: v0.10.4 (last version compatible with glibc 2.31)

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# Last release that works on glibc 2.31 (Ubuntu 20.04)
FALLBACK_VERSION="0.10.4"
MIN_GLIBC="2.32"

log "Installing Neovim..."

# Determine which version to install
GLIBC_VERSION=$(get_glibc_version)
if version_gte "$GLIBC_VERSION" "$MIN_GLIBC"; then
    VERSION=$(github_latest_version "neovim/neovim" --strip-v)
    log "glibc $GLIBC_VERSION >= $MIN_GLIBC — installing latest (v$VERSION)"
else
    VERSION="$FALLBACK_VERSION"
    log "glibc $GLIBC_VERSION < $MIN_GLIBC — installing v$VERSION (glibc 2.31 compatible)"
fi

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary nvim; then
    CURRENT=$(nvim --version 2>/dev/null | head -n1 | awk '{print $2}' | sed 's/^v//')
    if [[ "$CURRENT" == "$VERSION" ]]; then
        success "Neovim v$VERSION already installed"
        exit 0
    fi
    log "Neovim v$CURRENT installed, updating to v$VERSION..."
elif command -v nvim >/dev/null 2>&1; then
    warn "Existing nvim binary is broken — reinstalling"
fi

# Download and install
ARCH=$(get_arch)
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

TARBALL="nvim-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/v${VERSION}/${TARBALL}"

log "Downloading Neovim v${VERSION}..."
curl -Lo "$TARBALL" "$DOWNLOAD_URL"

# Remove old installation
rm -rf "$HOME/.local/nvim"
rm -f "$HOME/.local/bin/nvim"
mkdir -p "$HOME/.local/bin" "$HOME/.local"

log "Extracting to ~/.local/nvim..."
tar -C "$HOME/.local" -xzf "$TARBALL"
mv "$HOME/.local/nvim-linux-${ARCH}" "$HOME/.local/nvim"
ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"

# Verify
if "$HOME/.local/bin/nvim" --version >/dev/null 2>&1; then
    success "Neovim v$VERSION installed successfully!"
    "$HOME/.local/bin/nvim" --version | head -n1
else
    error "Neovim installation failed — binary does not run"
    exit 1
fi
