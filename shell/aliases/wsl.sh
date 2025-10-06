#!/bin/bash

# WSL-specific aliases and functions for Windows integration

# Only load these aliases on WSL systems
if ! command -v wslpath >/dev/null 2>&1; then
    return 0
fi

# Windows paths are now defined in shell/env.sh

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
# Explorer in current directory (also provides 'open' functionality)
explorer() {
    explorer.exe "${1:-.}"
}

# Alias for explorer
alias open='explorer'

# Clipboard integration
alias cwd='pwd | clip.exe'

# Windows path helper function
wcd() {
    local winpath=$(wslpath -w "$(pwd)")
    echo "$winpath" | clip.exe
    echo "Windows path copied to clipboard: $winpath"
}

# Path conversion
alias wpath='wslpath -w'
alias lpath='wslpath -u'

# SSH management (existing functionality)
alias win-ssh='ls -la $WIN_SSH'

# Functions are now in shell/wsl-functions.sh

# Note: Core WSL functions (SSH management, clipboard, etc.) are handled in lib.sh
# This file contains WSL-specific aliases

# SSH import functionality (main alias)
alias sync-ssh='import_windows_ssh_keys'