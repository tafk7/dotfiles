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
    local -n mapping_array=$1
    local -n result_array=$2
    local pm="$3"
    
    result_array=()
    
    for mapping in "${mapping_array[@]}"; do
        local package_name=""
        case "$pm" in
            apt)
                package_name=$(echo "$mapping" | cut -d: -f2)
                ;;
            dnf)
                package_name=$(echo "$mapping" | cut -d: -f3)
                ;;
            pacman)
                package_name=$(echo "$mapping" | cut -d: -f4)
                ;;
        esac
        
        # Skip packages marked as "SKIP"
        if [[ "$package_name" != "SKIP" && -n "$package_name" ]]; then
            result_array+=("$package_name")
        fi
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
        
        # Configure npm for user-space global installs if not already configured
        if [[ ! -d "$HOME/.npm-global" ]]; then
            mkdir -p "$HOME/.npm-global"
            npm config set prefix "$HOME/.npm-global"
            log "Configured npm for user-space global installations"
            
            # Add to PATH for current session
            export PATH="$HOME/.npm-global/bin:$PATH"
        fi
        
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
        
        # Try pipx first (preferred for tools in PEP 668 environments)
        if command -v pipx >/dev/null 2>&1; then
            if pipx install "$package" 2>/dev/null; then
                success "Installed Python package via pipx: $description"
                return 0
            fi
        fi
        
        # Try pip with --user flag
        if pip3 install --user "$package" 2>/dev/null; then
            success "Installed Python package: $description"
            return 0
        fi
        
        # Try with --break-system-packages as last resort (PEP 668 override)
        if pip3 install --user --break-system-packages "$package" 2>/dev/null; then
            success "Installed Python package (PEP 668 override): $description"
            return 0
        fi
        
        warn "Failed to install Python package: $description"
        log "Consider installing pipx: sudo apt install pipx"
        return 1
    else
        warn "pip3 not available, skipping Python package: $description"
        return 1
    fi
}