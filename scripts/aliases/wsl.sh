#!/bin/bash

# WSL-specific aliases and functions for Windows integration

# Windows paths
export WIN_HOME="/mnt/c/Users/$(whoami)"
export WIN_DESKTOP="$WIN_HOME/Desktop"
export WIN_DOWNLOADS="$WIN_HOME/Downloads"
export WIN_DOCUMENTS="$WIN_HOME/Documents"
export WIN_SSH="$WIN_HOME/.ssh"

# Navigation shortcuts
alias cdwin='cd $WIN_HOME'
alias cddesk='cd $WIN_DESKTOP'
alias cddl='cd $WIN_DOWNLOADS'
alias cddocs='cd $WIN_DOCUMENTS'

# Windows program shortcuts
alias open='explorer.exe'
alias notepad='notepad.exe'
alias clip='clip.exe'
alias pwsh='powershell.exe'
alias cmd='cmd.exe'

# File operations
alias explorer='explorer.exe .'
alias e='explorer.exe .'

# Clipboard integration
alias pbcopy='clip.exe'
alias pbpaste='powershell.exe -command "Get-Clipboard"'
alias cwd='pwd | clip.exe'

# Path conversion
alias wpath='wslpath -w'
alias lpath='wslpath -u'

# SSH management (existing functionality)
alias win-ssh='ls -la $WIN_SSH'
alias sync-ssh='copy-windows-ssh'

# Functions

# Launch Windows applications
winapp() {
    if [[ -z "$1" ]]; then
        echo "Usage: winapp <application> [args]"
        echo "Example: winapp chrome https://google.com"
        return 1
    fi
    cmd.exe /c start "$@"
}

# Open file with default Windows application
winopen() {
    if [[ -z "$1" ]]; then
        echo "Usage: winopen <file>"
        echo "Opens file with default Windows application"
        return 1
    fi
    if [[ -f "$1" ]]; then
        explorer.exe "$(wslpath -w "$1")"
    else
        echo "File not found: $1"
        return 1
    fi
}

# SSH Functions (moved from functions/ssh-helpers.sh)

# Copy SSH keys from Windows to WSL
copy-windows-ssh() {
    local windows_ssh="/mnt/c/Users/$(whoami)/.ssh"
    local wsl_ssh="$HOME/.ssh"
    
    if [[ ! -d "$windows_ssh" ]]; then
        echo "Windows SSH directory not found at $windows_ssh"
        return 1
    fi
    
    mkdir -p "$wsl_ssh"
    
    # Copy all SSH keys
    cp "$windows_ssh"/* "$wsl_ssh/" 2>/dev/null
    
    # Fix permissions
    chmod 700 "$wsl_ssh"
    chmod 600 "$wsl_ssh"/id_* 2>/dev/null
    chmod 644 "$wsl_ssh"/*.pub 2>/dev/null
    
    echo "SSH keys copied from Windows to WSL"
}

# List Windows SSH keys
list-windows-ssh() {
    ls -la "/mnt/c/Users/$(whoami)/.ssh/"
}

# Use specific Windows SSH key
use-windows-key() {
    local key_name=${1:-id_rsa}
    local windows_ssh="/mnt/c/Users/$(whoami)/.ssh"
    
    cp "$windows_ssh/$key_name" ~/.ssh/
    cp "$windows_ssh/$key_name.pub" ~/.ssh/
    chmod 600 ~/.ssh/$key_name
    chmod 644 ~/.ssh/$key_name.pub
    
    ssh-add ~/.ssh/$key_name
    echo "Added Windows SSH key: $key_name"
}