#!/bin/bash
# Simplified package management following Arete principles
# Trust the system, fail fast, keep it simple

# Source core functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/core.sh"

# Package definitions using associative array
declare -A PACKAGES=(
    [base]="build-essential curl wget git unzip zip jq software-properties-common zsh neovim bat fd-find ripgrep fzf python3-pip pipx openssh-client tmux"
    [wsl]="socat wslu"
    [work]="azure-cli nodejs npm docker.io docker-compose-v2"
    [personal]="ffmpeg yt-dlp"
)

# Simple package installation - trust apt
install_package_set() {
    local set_name="$1"
    local packages="${PACKAGES[$set_name]}"
    
    if [[ -z "$packages" ]]; then
        error "Unknown package set: $set_name"
        return 1
    fi
    
    log "Installing $set_name packages..."
    # shellcheck disable=SC2086
    if safe_sudo apt-get install -y $packages; then
        success "$set_name packages installed"
        return 0
    else
        # Some packages might fail, that's OK
        warn "Some $set_name packages failed to install"
        return 0
    fi
}

# Update package lists
update_packages() {
    log "Updating package lists..."
    safe_sudo apt-get update
}

# Install base packages
install_base_packages() {
    update_packages
    install_package_set "base"
    
    # Create command aliases for renamed packages
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        safe_sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        safe_sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
    
    # Setup NPM global directory
    setup_npm_global
}

# Install WSL-specific packages
install_wsl_packages() {
    is_wsl || return 0
    install_package_set "wsl"
}

# Install work packages with minimal setup
install_work_packages() {
    log "Installing work/development packages..."
    
    # For newer Ubuntu (22.04+), azure-cli is in universe
    if ! apt-cache show azure-cli >/dev/null 2>&1; then
        safe_sudo add-apt-repository -y universe
        update_packages
    fi
    
    install_package_set "work"
    
    # Add user to docker group if docker was installed
    if command -v docker >/dev/null 2>&1 && ! groups | grep -q docker; then
        safe_sudo usermod -aG docker "$USER"
        warn "Added to docker group. Log out and back in for changes to take effect."
    fi
}

# Install personal packages
install_personal_packages() {
    install_package_set "personal"
}

# Install specific tool if missing
ensure_tool() {
    local tool="$1"
    local package="${2:-$tool}"
    
    if command -v "$tool" >/dev/null 2>&1; then
        return 0
    fi
    
    log "Installing $tool..."
    if safe_sudo apt-get install -y "$package"; then
        success "$tool installed"
    else
        error "Failed to install $tool"
        return 1
    fi
}

# Main installation function
install_all_packages() {
    local include_work="${1:-false}"
    local include_personal="${2:-false}"
    
    install_base_packages
    install_wsl_packages
    
    if [[ "$include_work" == "true" ]]; then
        install_work_packages
    fi
    
    if [[ "$include_personal" == "true" ]]; then
        install_personal_packages
    fi
    
    success "Package installation complete"
}

# Export functions
export -f ensure_tool