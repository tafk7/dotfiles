#!/bin/bash
# Simplified package management following Arete principles
# Trust the system, fail fast, keep it simple

# Source core functions
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/core.sh"

# Package definitions using associative array
declare -A PACKAGES=(
    [core]="git build-essential"  # git is checked by installer, build-essential for compiling
    [development]="neovim zsh"  # removed curl, openssh-client (pre-installed)
    [modern]="bat fd-find ripgrep fzf"
    [terminal]="httpie htop tree"
    [languages]="python3-pip pipx"  # pip for direct use, pipx for isolated installs
    [wsl]="socat wslu"
    [docker]="docker.io docker-compose-v2"
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

# Install base packages - single apt transaction for efficiency
install_base_packages() {
    update_packages
    
    # Combine all base packages for single dependency resolution
    local all_base_packages="${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[modern]} ${PACKAGES[languages]} ${PACKAGES[terminal]}"
    
    # Add WSL packages if on WSL
    if is_wsl; then
        all_base_packages="$all_base_packages ${PACKAGES[wsl]}"
    fi
    
    log "Installing all base packages in single transaction..."
    # shellcheck disable=SC2086
    if safe_sudo apt-get install -y $all_base_packages; then
        success "Base packages installed successfully"
    else
        warn "Some packages failed to install (this is normal for some optional packages)"
    fi
    
    # Create command aliases for renamed packages
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        safe_sudo ln -sf "$(which batcat)" /usr/local/bin/bat
    fi
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        safe_sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    fi
    
    # Note: npm setup moved to install_node_and_npm()
}


# Install Node.js and configure npm properly
install_node_and_npm() {
    log "Installing Node.js and npm..."
    
    # Install Node.js via NodeSource repository for latest version
    if ! command -v node >/dev/null 2>&1; then
        log "Setting up NodeSource repository for Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | safe_sudo -E bash -
        safe_sudo apt-get install -y nodejs
    fi
    
    # NOW setup npm global directory after npm exists
    if command -v npm >/dev/null 2>&1; then
        setup_npm_global
    fi
}

# Install work packages
install_work_packages() {
    log "Installing work packages..."
    
    # Install Azure CLI
    if ! command -v az >/dev/null 2>&1; then
        log "Installing Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | safe_sudo bash
    fi
    
    # Install Docker
    install_package_set "docker"
    
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


# Note: Modern tools like eza, zoxide, starship are installed via separate scripts
# This keeps package management simple and version management flexible

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

# Main installation function (kept for compatibility)
install_all_packages() {
    local include_work="${1:-false}"
    local include_personal="${2:-false}"
    
    install_base_packages
    
    if [[ "$include_work" == "true" ]]; then
        install_node_and_npm
        install_work_packages
    fi
    
    if [[ "$include_personal" == "true" ]]; then
        install_personal_packages
    fi
    
    success "Package installation complete"
}

# Export functions
export -f ensure_tool