#!/bin/bash
# Install eget (GitHub release binary manager)
# Bootstraps eget itself, as versions.lock pins it; eget then installs the
# other binary tools.

set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component eget; exit; fi

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing eget v${EGET_VERSION}..."
if preserve_existing_tool eget "$FORCE"; then exit 2; fi

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

# The archive, its checksum, the file in it, and that file's digest.
IFS=$'\t' read -r _ _ _ _ EGET_ASSET EGET_ASSET_SHA256 EGET_MEMBER EGET_IDENTITY \
    < <(versions_row eget "$(get_arch)") || { error "versions.lock has no eget row for $(get_arch)"; exit 1; }

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
cd "$TEMP_DIR"

log "Downloading eget v${EGET_VERSION}..."
download_https "https://github.com/zyedidia/eget/releases/download/v${EGET_VERSION}/$EGET_ASSET" eget.tar.gz
verify_sha256 eget.tar.gz "$EGET_ASSET_SHA256" || exit 1

validate_tar_archive eget.tar.gz
tar xf eget.tar.gz
STAGED_EGET="$TEMP_DIR/$EGET_MEMBER"
[[ "$EGET_IDENTITY" != sha256:* ]] || verify_sha256 "$STAGED_EGET" "${EGET_IDENTITY#sha256:}" || exit 1
chmod +x "$STAGED_EGET"
"$STAGED_EGET" --version >/dev/null 2>&1 || { error "Staged eget binary does not run"; exit 1; }
atomic_replace_binary eget "$STAGED_EGET" "$HOME/.local/bin/eget"

# Verify by absolute path, not command -v: ~/.local/bin may not be on PATH yet
# on a fresh machine.
if "$HOME/.local/bin/eget" --version >/dev/null 2>&1; then
    success "eget v${EGET_VERSION} installed"
else
    error "eget installation failed — binary at \$HOME/.local/bin/eget does not run"
    exit 1
fi
