#!/bin/bash
# Environment detection and setup

# Global environment variables
DOTFILES_DIR=""
BACKUP_DIR=""
IS_WSL=false
WSL_VERSION=""
PACKAGE_MANAGER=""

# Initialize environment detection
init_environment() {
    # Set dotfiles directory
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    BACKUP_DIR="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    
    # Detect and validate environment
    detect_environment
    detect_package_manager
}

# Environment detection
detect_environment() {
    # Validate OS
    [[ ! "$OSTYPE" == "linux-gnu"* ]] && { error "Linux only. Detected: $OSTYPE"; exit 1; }
    
    # WSL detection
    if is_wsl; then
        IS_WSL=true
        WSL_VERSION=$(cat /proc/version | grep -o 'WSL[0-9]' || echo 'WSL1')
        wsl_log "Running in $WSL_VERSION environment"
    else
        IS_WSL=false
        log "Running on native Linux"
    fi
}

# Package manager detection
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
        log "Detected package manager: apt (Ubuntu/Debian)"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
        log "Detected package manager: dnf (Fedora/RHEL)"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
        log "Detected package manager: pacman (Arch)"
    else
        error "No supported package manager found (apt, dnf, or pacman)"
        exit 1
    fi
}

# Get package manager
get_package_manager() {
    echo "$PACKAGE_MANAGER"
}


# Export environment variables for use by other modules
export_environment() {
    export DOTFILES_DIR BACKUP_DIR IS_WSL WSL_VERSION PACKAGE_MANAGER
}