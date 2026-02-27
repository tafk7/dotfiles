#!/bin/bash
# Install tmux from source (GitHub releases)
# Compiles to ~/.local with --prefix, no sudo required
# Build deps (libevent-dev, libncurses-dev) must be present

set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing tmux..."

VERSION=$(github_latest_version "tmux/tmux" --strip-v)

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary tmux -V; then
    CURRENT=$(tmux -V 2>/dev/null | awk '{print $2}')
    if [[ "$CURRENT" == "$VERSION" ]]; then
        success "tmux $VERSION already installed"
        exit 2
    fi
    log "tmux $CURRENT installed, updating to $VERSION..."
fi

# Verify build dependencies
for dep in bison libevent-dev libncurses-dev; do
    if ! dpkg -s "$dep" >/dev/null 2>&1; then
        error "Missing build dependency: $dep (install with: sudo apt install $dep)"
        exit 1
    fi
done

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

TARBALL="tmux-${VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/tmux/tmux/releases/download/${VERSION}/${TARBALL}"

log "Downloading tmux $VERSION..."
curl -Lo "$TARBALL" "$DOWNLOAD_URL"

log "Extracting..."
tar -xzf "$TARBALL"
cd "tmux-${VERSION}"

log "Configuring (--prefix=$HOME/.local)..."
BUILD_LOG="$TEMP_DIR/build.log"
if ! ./configure --prefix="$HOME/.local" >"$BUILD_LOG" 2>&1; then
    error "configure failed — build log:"
    tail -30 "$BUILD_LOG"
    exit 1
fi

log "Compiling..."
if ! make -j"$(nproc)" >>"$BUILD_LOG" 2>&1; then
    error "make failed — build log:"
    tail -30 "$BUILD_LOG"
    exit 1
fi

log "Installing to ~/.local/bin..."
make install >>"$BUILD_LOG" 2>&1

# Verify
if "$HOME/.local/bin/tmux" -V >/dev/null 2>&1; then
    success "tmux $VERSION installed successfully!"
    "$HOME/.local/bin/tmux" -V
else
    error "tmux installation failed — binary does not run"
    exit 1
fi
