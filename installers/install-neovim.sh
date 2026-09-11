#!/bin/bash
# Install Neovim from GitHub releases
# glibc >= 2.32: latest release
# glibc <  2.32: v0.10.4 (last version compatible with glibc 2.31)

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# Last release that works on glibc 2.31 (Ubuntu 20.04)
FALLBACK_VERSION="0.10.4"
MIN_GLIBC="2.32"

# Pipe-free version probe. `nvim --version | head -n1` returns 141 when head exits
# before nvim finishes writing (SIGPIPE), and `set -o pipefail` makes that fatal.
nvim_version() {
    local out
    out=$(nvim --version 2>/dev/null) || return 1
    out=${out%%$'\n'*}
    out=${out##* }
    printf '%s\n' "${out#v}"
}

log "Installing Neovim..."

# Determine which version to install
GLIBC_VERSION=$(get_glibc_version)
if version_gte "$GLIBC_VERSION" "$MIN_GLIBC"; then
    VERSION=$(github_latest_version "neovim/neovim" --strip-v) || {
        # If API fails (rate-limited) and --force, fall back to reinstalling current
        if [[ "$FORCE" == true ]] && verify_binary nvim; then
            VERSION=$(nvim_version)
            warn "GitHub API unavailable — reinstalling current v$VERSION"
        else
            error "Failed to fetch latest Neovim version"
            exit 1
        fi
    }
    log "glibc $GLIBC_VERSION >= $MIN_GLIBC — installing latest (v$VERSION)"
else
    VERSION="$FALLBACK_VERSION"
    log "glibc $GLIBC_VERSION < $MIN_GLIBC — installing v$VERSION (glibc 2.31 compatible)"
fi

# Check existing installation
if [[ "$FORCE" != true ]] && verify_binary nvim; then
    CURRENT=$(nvim_version)
    if [[ "$CURRENT" == "$VERSION" ]]; then
        success "Neovim v$VERSION already installed"
        exit 2
    fi
    log "Neovim v$CURRENT installed, updating to v$VERSION..."
elif command -v nvim >/dev/null 2>&1; then
    warn "Existing nvim binary is broken — reinstalling"
fi

# Download and install.
# get_arch() returns aarch64, but upstream Neovim names its ARM asset
# nvim-linux-arm64.tar.gz (and the dir inside likewise). Map accordingly.
ARCH=$(get_arch)
case "$ARCH" in
    x86_64)  NVIM_ARCH="x86_64" ;;
    aarch64) NVIM_ARCH="arm64" ;;
    *)       error "Unsupported architecture for Neovim: $ARCH"; exit 1 ;;
esac
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

TARBALL="nvim-linux-${NVIM_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/v${VERSION}/${TARBALL}"

log "Downloading Neovim v${VERSION}..."
download_https "$DOWNLOAD_URL" "$TARBALL"

log "Extracting staged Neovim tree..."
validate_tar_archive "$TARBALL"
tar -C "$TEMP_DIR" -xzf "$TARBALL"
STAGED_TREE="$TEMP_DIR/nvim-linux-${NVIM_ARCH}"
[[ -x "$STAGED_TREE/bin/nvim" ]] || { error "Neovim archive did not contain the expected binary"; exit 1; }
"$STAGED_TREE/bin/nvim" --version >/dev/null 2>&1 || { error "Staged Neovim binary does not run"; exit 1; }

mkdir -p "$HOME/.local/bin" "$HOME/.local"
atomic_replace_tree neovim "$STAGED_TREE" "$HOME/.local/nvim" bin/nvim
ln -sfn "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"

# Verify
if "$HOME/.local/bin/nvim" --version >/dev/null 2>&1; then
    success "Neovim v$VERSION installed successfully!"
    "$HOME/.local/bin/nvim" --version | head -n1
else
    error "Neovim installation failed — binary does not run"
    exit 1
fi
