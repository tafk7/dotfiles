#!/bin/bash
# All WSL-specific runtime concerns — functions and aliases.
# Sourced conditionally by shell/init.sh when DOTFILES_WSL=1.
# No WSL guard needed here — init.sh handles the check.

# ==============================================================================
# Functions
# ==============================================================================

# Launch Windows applications
winapp() {
    if [[ -z "$1" ]]; then
        echo "Usage: winapp <application> [args]"
        return 1
    fi
    cmd.exe /c start "$@"
}

# Open file with default Windows application
winopen() {
    if [[ -z "$1" ]]; then
        echo "Usage: winopen <file>"
        return 1
    fi
    if [[ -f "$1" ]]; then
        explorer.exe "$(wslpath -w "$1")"
    else
        echo "File not found: $1"
        return 1
    fi
}

# Explorer in current directory
explorer() {
    explorer.exe "${1:-.}"
}

# Copy current Windows path to clipboard
wcd() {
    local winpath
    winpath=$(wslpath -w "$(pwd)")
    echo "$winpath" | clip.exe
    echo "Windows path copied to clipboard: $winpath"
}

# ==============================================================================
# Aliases
# ==============================================================================

# Navigation
alias cdwin='cd $WIN_HOME'
alias cddesk='cd $WIN_DESKTOP'
alias cddl='cd $WIN_DOWNLOADS'
alias cddocs='cd $WIN_DOCUMENTS'

# Windows programs
alias notepad='notepad.exe'
alias clip='clip.exe'
alias cmd='cmd.exe'
alias winget='/mnt/c/Windows/System32/winget.exe'

# PowerShell — call by absolute path. shell/env.sh strips the Windows
# PowerShell directory from PATH, so `powershell.exe` by name would not resolve.
if [[ -x "/mnt/c/Program Files/PowerShell/7/pwsh.exe" ]]; then
    alias pwsh='/mnt/c/Program\ Files/PowerShell/7/pwsh.exe'
else
    alias pwsh='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
fi

# File operations
alias open='explorer'
alias cwd='pwd | clip.exe'

# Path conversion
alias wpath='wslpath -w'
alias lpath='wslpath -u'
