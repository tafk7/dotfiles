#!/bin/bash
# Install NVM (Node Version Manager) at the version versions.lock pins, and
# move an NVM dotfiles installed when the pin moves; NVM's installer updates it
# in place. An NVM dotfiles did not install is left alone unless --force. The
# Node release is install-node.sh's.

set -eo pipefail  # Remove -u flag to avoid NVM's unbound variable issues

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component nvm; exit; fi

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

log "Installing NVM (Node Version Manager)..."

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# The installed version: package.json in a Git checkout, else NVM's own
# report.
nvm_version() {
    local version
    version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$NVM_DIR/package.json" 2>/dev/null | head -n1)"
    # shellcheck disable=SC2016
    [[ -n "$version" ]] || version="$(bash -c '. "$1/nvm.sh" --no-use >/dev/null 2>&1 && nvm --version' _ "$NVM_DIR" 2>/dev/null || true)"
    printf '%s\n' "$version"
}

if [[ "$FORCE" != true && -s "$NVM_DIR/nvm.sh" ]]; then
    owner=""
    IFS=$'\t' read -r _ _ owner _ < <(ledger_line nvm 2>/dev/null || true) || true
    if [[ "$owner" != dotfiles ]]; then
        log "Preserving an NVM dotfiles does not own at $NVM_DIR; --force adopts it"
        exit 2
    fi
    current="$(nvm_version)"
    if [[ "$current" == "$NVM_VERSION" ]]; then
        success "NVM $NVM_VERSION is installed at $NVM_DIR"
        exit 2
    fi
    log "NVM ${current:-of unknown version} installed, moving to $NVM_VERSION..."
fi

mkdir -p "$NVM_DIR"

# Download to a file rather than piping the network into bash.
log "Downloading NVM installer (v$NVM_VERSION)..."
nvm_installer="${DOTFILES_NVM_INSTALLER_SCRIPT:-}"
downloaded_installer=false
if [[ -z "$nvm_installer" ]]; then
    nvm_installer="$(mktemp)"
    downloaded_installer=true
    download_installer_script "https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh" "$nvm_installer"
    verify_sha256 "$nvm_installer" "$(versions_field nvm sha256 any)" || { rm -f "$nvm_installer"; exit 1; }
elif [[ ! -s "$nvm_installer" ]]; then
    error "DOTFILES_NVM_INSTALLER_SCRIPT is missing or empty: $nvm_installer"
    exit 1
fi
log "Running NVM installer from $nvm_installer"
# PROFILE=/dev/null stops the installer editing shell rc files, which are
# symlinks into this repo. shell/lazy/nvm.sh and the $NVM_DIR/default
# symlink already wire NVM up, and the appended block would load it eagerly.
# NVM uses unbound variables internally, so it runs without -u.
if ! env PROFILE=/dev/null bash "$nvm_installer"; then
    [[ "$downloaded_installer" == true ]] && rm -f "$nvm_installer"
    error "NVM installer failed; any prior installation was left in place"
    exit 1
fi
[[ "$downloaded_installer" == true ]] && rm -f "$nvm_installer"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    error "NVM installation failed"
    exit 1
fi
installed="$(nvm_version)"
[[ "$installed" == "$NVM_VERSION" ]] || { error "NVM reports ${installed:-no version} after installing $NVM_VERSION"; exit 1; }
success "NVM $NVM_VERSION installed"
