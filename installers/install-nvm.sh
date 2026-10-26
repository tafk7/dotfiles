#!/bin/bash
# Install NVM (Node Version Manager). The Node release it installs is
# install-node.sh's, as versions.lock pins it.

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

if [[ "$FORCE" != true && -s "$NVM_DIR/nvm.sh" ]]; then
    success "NVM is already installed at $NVM_DIR"
    exit 2
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
success "NVM installed successfully!"
