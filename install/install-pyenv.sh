#!/bin/bash
# Install pyenv (Python Version Manager)
# Best practice for Python development - manage multiple Python versions

set -eo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib.sh"

log "Installing pyenv (Python Version Manager)..."

# pyenv installation directory
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"

# Check if already installed
if [[ -d "$PYENV_ROOT" ]] && [[ -x "$PYENV_ROOT/bin/pyenv" ]]; then
    log "pyenv is already installed at $PYENV_ROOT"

    # Source pyenv to check version
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path 2>/dev/null || true)"
    eval "$(pyenv init - 2>/dev/null || true)"

    pyenv --version

    # Show installed Python versions
    if pyenv versions --bare 2>/dev/null | grep -q .; then
        log "Installed Python versions:"
        pyenv versions
    else
        log "pyenv is installed but no Python versions are installed yet."
        log "Use: pyenv install <version> (e.g., pyenv install 3.11.9)"
    fi

    exit 2
fi

# Install build dependencies
log "Installing Python build dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    curl \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    llvm \
    git

success "Build dependencies installed!"

# Download and install pyenv
log "Downloading pyenv installer..."
curl -fsSL https://pyenv.run | bash

# Verify installation
if [[ ! -x "$PYENV_ROOT/bin/pyenv" ]]; then
    error "pyenv installation failed"
    exit 1
fi

success "pyenv installed successfully!"

# Source pyenv for current session
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv init -)"

# Verify pyenv is working
if command -v pyenv >/dev/null 2>&1; then
    success "pyenv $(pyenv --version) is ready to use!"

    log ""
    log "Next steps:"
    log "1. Reload your shell: exec \$SHELL"
    log "2. Install Python versions: pyenv install 3.11.9"
    log "3. See available versions: pyenv install --list"
    log "4. Set version for project: cd /path/to/project && pyenv local 3.11.9"
    log ""
    log "pyenv will be automatically loaded in new shell sessions"
else
    error "pyenv installation verification failed"
    exit 1
fi

# Show a few recommended Python versions
log ""
log "Recommended Python versions to install:"
log "  - Python 3.11.x (stable, widely supported)"
log "  - Python 3.12.x (latest stable)"
log "  - Python 3.10.x (for compatibility)"
log ""
log "Example: pyenv install 3.11.9 && pyenv install 3.12.4"
