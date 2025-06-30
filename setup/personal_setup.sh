#!/bin/bash
# Personal setup script - Personal tools and entertainment  
# This file is sourced by install.sh when --personal flag is used

# Main personal package installation function
install_personal_packages() {
    log "Installing personal packages..."
    
    # Get package manager type
    local pm=$(get_package_manager)
    
    # Define personal package mappings: generic:apt:dnf:pacman
    local personal_mappings=(
        # Media tools (command-line only)
        "ffmpeg:ffmpeg:ffmpeg:ffmpeg"
    )
    
    # Build and install personal packages
    local packages=()
    build_package_list personal_mappings packages "$pm"
    install_packages packages "personal packages"
    
    success "Personal environment configured"
}
