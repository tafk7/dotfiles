#!/bin/bash
# Install NVM (Node Version Manager) and Node.js

set -eo pipefail  # Remove -u flag to avoid NVM's unbound variable issues

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# NVM uses unbound variables internally, so run it with -u disabled.
run_nvm_command() {
    set +u
    "$@"
    local exit_code=$?
    set -u
    return $exit_code
}

log "Installing NVM (Node Version Manager)..."

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Keep a Windows npm on PATH from shadowing NVM's.
if [[ -n "${PATH:-}" ]]; then
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/mnt/c/' | tr '\n' ':' | sed 's/:$//')
    export PATH
fi

if [[ "$FORCE" != true && -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log "NVM is already installed at $NVM_DIR"
    run_nvm_command . "$NVM_DIR/nvm.sh"
    nvm --version

    if command -v node >/dev/null 2>&1; then
        log "Node.js $(node --version) is already installed via NVM"
        log "npm $(npm --version) is available"
        exit 2
    else
        log "NVM is installed but Node.js is not. Installing Node.js LTS..."
    fi
else
    mkdir -p "$NVM_DIR"

    # Download to a file rather than piping the network into bash.
    log "Downloading NVM installer (v0.40.4)..."
    nvm_installer="${DOTFILES_NVM_INSTALLER_SCRIPT:-}"
    downloaded_installer=false
    if [[ -z "$nvm_installer" ]]; then
        nvm_installer="$(mktemp)"
        downloaded_installer=true
        download_installer_script "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh" "$nvm_installer"
    elif [[ ! -s "$nvm_installer" ]]; then
        error "DOTFILES_NVM_INSTALLER_SCRIPT is missing or empty: $nvm_installer"
        exit 1
    fi
    log "Running NVM installer from $nvm_installer"
    # PROFILE=/dev/null stops the installer editing shell rc files, which are
    # symlinks into this repo. shell/lazy/nvm.sh and the $NVM_DIR/default
    # symlink already wire NVM up, and the appended block would load it eagerly.
    if ! run_nvm_command env PROFILE=/dev/null bash "$nvm_installer"; then
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
fi

log "Loading NVM..."
export NVM_DIR="$HOME/.nvm"
run_nvm_command . "$NVM_DIR/nvm.sh"

log "Installing latest LTS Node.js..."
run_nvm_command nvm install --lts
run_nvm_command nvm use --lts
run_nvm_command nvm alias default lts/*

if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    success "Node.js $(node --version) and npm $(npm --version) installed via NVM!"

    log "Updating npm to latest version..."
    if run_nvm_command npm install -g npm@latest >/dev/null 2>&1; then
        success "npm updated to $(npm --version)"
    else
        warn "npm update failed, using version $(npm --version)"
    fi

    # A stable symlink lets shell/env.sh put Node on PATH without sourcing
    # nvm.sh, which non-interactive shells never do.
    default_version=$(node --version)
    if [[ -d "$NVM_DIR/versions/node/$default_version" ]]; then
        ln -sfn "$NVM_DIR/versions/node/$default_version" "$NVM_DIR/default"
        success "Symlinked $NVM_DIR/default → $default_version"
    fi

    log "NVM will be automatically loaded in new shell sessions"
    log "To use in current session: source ~/.bashrc (or ~/.zshrc)"
else
    error "Node.js installation via NVM failed"
    exit 1
fi
