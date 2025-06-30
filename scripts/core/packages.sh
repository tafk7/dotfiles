#!/bin/bash
# Unified package management system

# safe_sudo function is now available from common.sh (loaded by install.sh)

# Update system packages
update_system() {
    log "Updating system packages..."
    
    case "$(get_package_manager)" in
        apt)
            safe_sudo apt update && safe_sudo apt upgrade -y
            ;;
        dnf)
            safe_sudo dnf update -y
            ;;
        pacman)
            safe_sudo pacman -Syu --noconfirm
            ;;
    esac
    
    success "System packages updated"
}

# Unified package installation function
install_packages() {
    local -n package_array=$1
    local description="$2"
    
    [[ ${#package_array[@]} -eq 0 ]] && return 0
    
    log "Installing $description..."
    
    case "$(get_package_manager)" in
        apt)
            safe_sudo apt install -y "${package_array[@]}"
            ;;
        dnf)
            safe_sudo dnf install -y "${package_array[@]}"
            ;;
        pacman)
            safe_sudo pacman -S --noconfirm "${package_array[@]}"
            ;;
    esac
    
    success "Installed $description"
}

# Install single package with error handling
install_single_package() {
    local package="$1"
    local description="${2:-$package}"
    
    log "Installing $description..."
    
    case "$(get_package_manager)" in
        apt)
            if safe_sudo apt install -y "$package"; then
                success "Installed $description"
                return 0
            fi
            ;;
        dnf)
            if safe_sudo dnf install -y "$package"; then
                success "Installed $description"
                return 0
            fi
            ;;
        pacman)
            if safe_sudo pacman -S --noconfirm "$package"; then
                success "Installed $description"
                return 0
            fi
            ;;
    esac
    
    warn "Failed to install $description"
    return 1
}

# Build package list from mapping
build_package_list() {
    local -n mappings=$1
    local -n packages=$2
    local pm="$3"
    
    packages=()
    
    for mapping in "${mappings[@]}"; do
        case "$pm" in
            apt)
                packages+=($(echo "$mapping" | cut -d: -f2))
                ;;
            dnf)
                packages+=($(echo "$mapping" | cut -d: -f3))
                ;;
            pacman)
                packages+=($(echo "$mapping" | cut -d: -f4))
                ;;
        esac
    done
}

# Resolve package name for current package manager
resolve_package_name() {
    local mapping="$1"
    local pm="$(get_package_manager)"
    
    case "$pm" in
        apt) echo "$mapping" | cut -d: -f2 ;;
        dnf) echo "$mapping" | cut -d: -f3 ;;
        pacman) echo "$mapping" | cut -d: -f4 ;;
    esac
}

# Install snap packages
install_snaps() {
    local -a snap_packages=("$@")
    
    [[ ${#snap_packages[@]} -eq 0 ]] && return 0
    
    if command -v snap >/dev/null 2>&1; then
        log "Installing Snap packages..."
        for package in "${snap_packages[@]}"; do
            if safe_sudo snap install "$package"; then
                success "Installed snap: $package"
            else
                warn "Failed to install snap: $package"
            fi
        done
    else
        warn "Snapd not available, skipping snap packages"
    fi
}

# Install NPM packages globally
install_npm_packages() {
    local -a npm_packages=("$@")
    
    [[ ${#npm_packages[@]} -eq 0 ]] && return 0
    
    if command -v npm >/dev/null 2>&1; then
        log "Installing NPM packages..."
        for package in "${npm_packages[@]}"; do
            if npm install -g "$package"; then
                success "Installed npm: $package"
            else
                warn "Failed to install npm: $package"
            fi
        done
    else
        warn "NPM not available, skipping npm packages"
    fi
}

# Install VS Code extensions
install_vscode_extensions() {
    local -a extensions=("$@")
    
    [[ ${#extensions[@]} -eq 0 ]] && return 0
    
    if command -v code >/dev/null 2>&1; then
        log "Installing VS Code extensions..."
        for extension in "${extensions[@]}"; do
            if code --install-extension "$extension"; then
                success "Installed VS Code extension: $extension"
            else
                warn "Failed to install VS Code extension: $extension"
            fi
        done
    else
        warn "VS Code not available, skipping extensions"
    fi
}

# Install Python package with pip3
install_python_package() {
    local package="$1"
    local description="${2:-$package}"
    
    if command -v pip3 >/dev/null 2>&1; then
        log "Installing Python package: $description..."
        if pip3 install --user "$package"; then
            success "Installed Python package: $description"
            return 0
        else
            warn "Failed to install Python package: $description"
            return 1
        fi
    else
        warn "pip3 not available, skipping Python package: $description"
        return 1
    fi
}