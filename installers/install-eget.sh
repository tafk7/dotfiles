#!/bin/bash
# Install eget (GitHub release binary manager)
# Bootstraps eget itself — all other binary tools are then managed via eget.toml

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

EGET_VERSION="1.3.4"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing eget v${EGET_VERSION}..."
if preserve_existing_tool eget "$FORCE"; then exit 2; fi

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
download_https "https://github.com/zyedidia/eget/releases/download/v${EGET_VERSION}/eget-${EGET_VERSION}-linux_${EGET_ARCH}.tar.gz" eget.tar.gz

validate_tar_archive eget.tar.gz
tar xf eget.tar.gz
STAGED_EGET="$TEMP_DIR/eget-${EGET_VERSION}-linux_${EGET_ARCH}/eget"
chmod +x "$STAGED_EGET"
"$STAGED_EGET" --version >/dev/null 2>&1 || { error "Staged eget binary does not run"; exit 1; }
atomic_replace_binary eget "$STAGED_EGET" "$HOME/.local/bin/eget"

# Verify the binary we just wrote, by absolute path — NOT via command -v. On a
# fresh machine ~/.local/bin isn't on PATH yet (Ubuntu's ~/.profile only adds it
# if it existed at login, and the dotfiles shell configs aren't loaded in this
# session), so a PATH lookup would report a false failure for a perfectly good
# install. Same reason install_eget_tools resolves eget by absolute path.
if "$HOME/.local/bin/eget" --version >/dev/null 2>&1; then
    success "eget v${EGET_VERSION} installed"
else
    error "eget installation failed — binary at \$HOME/.local/bin/eget does not run"
    exit 1
fi
