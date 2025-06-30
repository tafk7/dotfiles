#!/bin/bash

# Personal setup script - Personal tools and entertainment
# This file is sourced by install.sh when --personal flag is used

personal_log "Configuring personal environment..."

# Get package manager type
pm=$(get_package_manager)
[[ "$pm" == "unknown" ]] && { warn "Unknown package manager for $DISTRO"; return 1; }

# Define personal package mappings
declare -a personal_package_mappings=(
    # Media tools
    "ffmpeg"
    
    # Add packages as needed
)

# Build and install personal packages
declare -a personal_packages
build_package_list personal_package_mappings personal_packages "$pm"
install_packages personal_packages "personal"

# Create personal directories and aliases

success "Personal environment configured"
