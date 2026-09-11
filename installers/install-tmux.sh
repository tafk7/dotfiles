#!/bin/bash
# Install tmux from source (GitHub releases)
# Compiles to ~/.local with --prefix, no sudo required
# Build deps (libevent-dev, libncurses-dev) must be present

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

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
download_https "$DOWNLOAD_URL" "$TARBALL"

log "Extracting..."
validate_tar_archive "$TARBALL"
tar -xzf "$TARBALL"
cd "tmux-${VERSION}"

STAGE_PREFIX="$TEMP_DIR/prefix"
log "Configuring staged prefix..."
BUILD_LOG="$TEMP_DIR/build.log"
if ! ./configure --prefix="$STAGE_PREFIX" >"$BUILD_LOG" 2>&1; then
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

log "Installing into staging..."
make install >>"$BUILD_LOG" 2>&1

[[ -x "$STAGE_PREFIX/bin/tmux" ]] || { error "Staged tmux binary is missing"; exit 1; }
"$STAGE_PREFIX/bin/tmux" -V >/dev/null 2>&1 || { error "Staged tmux binary does not run"; exit 1; }
atomic_replace_binary tmux "$STAGE_PREFIX/bin/tmux" "$HOME/.local/bin/tmux"

# Verify
if "$HOME/.local/bin/tmux" -V >/dev/null 2>&1; then
    success "tmux $VERSION installed successfully!"
    "$HOME/.local/bin/tmux" -V
else
    error "tmux installation failed — binary does not run"
    exit 1
fi
