#!/bin/bash

# Base setup script - Core packages and configurations for everyone
# This file is sourced by install.sh

# Enable strict error handling
set -e
set -u
set -o pipefail

# Error trap for cleanup
trap 'handle_error "base_setup.sh at line $LINENO"' ERR

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

# Install packages with retry logic
log "Installing base packages..."
if ! retry_network_operation 3 5 "install_packages base_packages 'base'"; then
    error "Failed to install base packages after retries"
    return 1
fi

if [[ "$IS_WSL" == true ]]; then
    wsl_log "Installing WSL-specific packages..."
    if ! retry_network_operation 3 5 "install_packages wsl_packages 'WSL'"; then
        warn "Failed to install some WSL packages"
    fi
fi

success "Base packages installed"
