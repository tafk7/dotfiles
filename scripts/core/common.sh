#!/bin/bash

# Common utilities shared across modules to avoid circular dependencies

# Check if running in WSL
is_wsl() {
    if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || [[ -n "${WSL_DISTRO_NAME}" ]]; then
        return 0
    else
        return 1
    fi
}

# Get Windows username for WSL environments
get_windows_username() {
    # Method 1: Try using cmd.exe (most reliable)
    if command -v cmd.exe &> /dev/null; then
        local windows_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
        if [[ -n "$windows_user" && "$windows_user" != "%USERNAME%" ]]; then
            echo "$windows_user"
            return
        fi
    fi
    
    # Method 2: Default to Linux username
    echo "$USER"
}

# Safe sudo wrapper with user confirmation
safe_sudo() {
    # Check if we're already root
    [[ $EUID -eq 0 ]] && {
        "$@"
        return $?
    }
    
    # Show command for transparency
    log "Running with sudo: $*"
    
    # Execute with sudo
    sudo "$@"
    return $?
}