#!/bin/bash
# Base setup script - Core packages and configurations for everyone
# This file is sourced by install.sh
# safe_sudo function is available from common.sh (loaded by install.sh)

# Main base package installation function
install_base_packages() {
    log "Installing base packages..."
    
    # Get package manager type
    local pm=$(get_package_manager)
    
    # Define base package mappings: generic:apt:dnf:pacman
    local base_package_mappings=(
        # Essential tools
        "build-essential:build-essential:make gcc gcc-c++ kernel-devel:base-devel"
        "curl:curl:curl:curl"
        "wget:wget:wget:wget"
        "git:git:git:git"
        "vim:vim:vim:vim"
        "unzip:unzip:unzip:unzip"
        "zip:zip:zip:zip"
        "jq:jq:jq:jq"
        
        # Shell
        "zsh:zsh:zsh:zsh"
        
        # Modern CLI tools
        "eza:eza:eza:eza"
        "bat:bat:bat:bat"
        "fd:fd-find:fd-find:fd"
        "ripgrep:ripgrep:ripgrep:ripgrep"
        "fzf:fzf:fzf:fzf"
        "tree:tree:tree:tree"
        "htop:htop:htop:htop"
        "glow:SKIP:SKIP:glow"  # Markdown viewer (apt/dnf need external repo)
        
        # Development
        "python3-pip:python3-pip:python3-pip:python-pip"
        "pipx:pipx:pipx:python-pipx"
        "nodejs:nodejs:nodejs:nodejs"
        "npm:npm:npm:npm"
        
        # System utilities
        "net-tools:net-tools:net-tools:net-tools"
        "fontconfig:fontconfig:fontconfig:fontconfig"
        "openssh-client:openssh-client:openssh-clients:openssh"
    )
    
    # Build package list for current package manager
    local packages=()
    build_package_list base_package_mappings packages "$pm"
    
    # Install base packages
    install_packages packages "base packages"
    
    # Install Docker separately (requires special handling)
    install_docker
    
    # Install Glow markdown viewer (requires special handling for apt/dnf)
    install_glow
    
    # WSL-specific packages
    if is_wsl; then
        install_wsl_packages "$pm"
    fi
    
    success "Base packages installation completed"
}

# Install Docker with distribution-specific handling
install_docker() {
    log "Installing Docker..."
    
    case "$(get_package_manager)" in
        apt)
            # Add Docker's official GPG key and repository (modern method)
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | safe_sudo tee /usr/share/keyrings/docker-archive-keyring.gpg > /dev/null
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | safe_sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            safe_sudo apt update
            install_single_package "docker-ce" "Docker"
            install_single_package "docker-compose" "Docker Compose"
            ;;
        dnf)
            install_single_package "docker" "Docker"
            install_single_package "docker-compose" "Docker Compose"
            ;;
        pacman)
            install_single_package "docker" "Docker"
            install_single_package "docker-compose" "Docker Compose"
            ;;
    esac
    
    # Add user to docker group
    if groups | grep -q docker; then
        log "User already in docker group"
    else
        safe_sudo usermod -aG docker "$USER"
        success "Added user to docker group (restart shell to take effect)"
    fi
}

# Install Glow markdown viewer with special handling
install_glow() {
    log "Installing Glow markdown viewer..."
    
    case "$(get_package_manager)" in
        apt|dnf)
            # Try snap first as it's simpler than adding repos
            if command -v snap >/dev/null 2>&1; then
                if safe_sudo snap install glow; then
                    success "Installed Glow via snap"
                    return 0
                fi
            fi
            warn "Glow requires external repository on $(get_package_manager)"
            log "Install manually from: https://github.com/charmbracelet/glow"
            log "Or use: snap install glow"
            ;;
        pacman)
            # Already handled by package mapping - glow is in Arch repos
            log "Glow installed via pacman"
            ;;
    esac
}

# Install WSL-specific packages
install_wsl_packages() {
    local pm="$1"
    
    wsl_log "Installing WSL-specific packages..."
    
    local wsl_mappings=(
        "socat:socat:socat:socat"
        "wslu:wslu:wslu:wslu"
    )
    
    local wsl_packages=()
    build_package_list wsl_mappings wsl_packages "$pm"
    
    install_packages wsl_packages "WSL packages"
}
