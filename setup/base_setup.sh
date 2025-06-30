#!/bin/bash

# Base setup script - Core packages and configurations for everyone
# This file is sourced by install.sh

log "Configuring base environment..."

# Get package manager type
pm=$(get_package_manager)
[[ "$pm" == "unknown" ]] && { warn "Unknown package manager for $DISTRO"; return 1; }

# Define base package mappings
declare -a base_package_mappings=(
    # Shell and terminal
    "zsh" "tmux" "git" "curl" "wget"
    
    # Modern CLI tools
    "exa:eza:eza:eza"
    "bat:bat:bat:bat" 
    "fd:fd-find:fd-find:fd"
    "ripgrep" "fzf" "tree" "htop" "ncdu" "neofetch"
    
    # Development essentials
    "build-tools:build-essential:make gcc gcc-c++ kernel-devel:base-devel"
    "python-pip:python3-pip:python3-pip:python-pip"
    "nodejs" "npm" "vim"
    
    # Containers
    "docker:docker.io:docker:docker"
    "docker-compose:docker-compose:docker-compose:docker-compose"
    
    # System utilities
    "unzip" "zip" "jq" "net-tools" "fontconfig"
    "openssh-client:openssh-clients:openssh:openssh"
)

# WSL-specific packages
declare -a wsl_package_mappings=(
    "socat" "wslu"
)

# Build package arrays
declare -a base_packages wsl_packages
build_package_list base_package_mappings base_packages "$pm"

if [[ "$IS_WSL" == true ]]; then
    build_package_list wsl_package_mappings wsl_packages "$pm"
fi

# Install packages
install_packages base_packages "base"

if [[ "$IS_WSL" == true ]]; then
    wsl_log "Installing WSL-specific packages..."
    install_packages wsl_packages "WSL"
fi

success "Base packages installed"
