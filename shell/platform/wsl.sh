#!/bin/bash
# WSL-specific functions and aliases. shell/init.sh only sources this on WSL.

# ==============================================================================
# SSH agent bridge — OPT-IN per machine
# ==============================================================================
#
# Forwards the Windows ssh-agent into WSL so keys stay in the vault. Enabled by
# the ~/.ssh/use-windows-agent marker (a file, not an env var, because this runs
# before ~/.shell.local). The systemd user service normally runs the relay; this
# points SSH_AUTH_SOCK at its socket and starts the relay inline only if the
# socket is dead (no systemd, or marker added after setup). Without the marker,
# SSH_AUTH_SOCK is untouched. See docs/customization.md.
if [[ -f "$HOME/.ssh/use-windows-agent" ]]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/wsl2-ssh-agent.sock"
    # exit 2 from ssh-add = "can't connect" (dead socket) -> revive inline.
    ssh-add -l >/dev/null 2>&1
    if [[ $? -eq 2 ]] && command -v wsl2-ssh-agent >/dev/null 2>&1; then
        eval "$(wsl2-ssh-agent)" >/dev/null 2>&1
    fi
fi

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
