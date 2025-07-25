#!/bin/bash

# WSL-specific aliases and functions for Windows integration

# Only load these aliases on WSL systems
if ! command -v wslpath >/dev/null 2>&1; then
    return 0
fi

# Windows paths - using $USER instead of $(whoami) for security
export WIN_HOME="/mnt/c/Users/$USER"
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
alias notepad='notepad.exe'
alias clip='clip.exe'
alias pwsh='powershell.exe'
alias cmd='cmd.exe'

# File operations
alias explorer='explorer.exe .'

# Clipboard integration
alias cwd='pwd | clip.exe'

# Path conversion
alias wpath='wslpath -w'
alias lpath='wslpath -u'

# SSH management (existing functionality)
alias win-ssh='ls -la $WIN_SSH'

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

# Note: Core WSL functions (SSH management, clipboard, etc.) are handled in wsl/core.sh
# This file only contains simple aliases and basic functions

# SSH import functionality (main alias)
alias sync-ssh='import_windows_ssh_keys'