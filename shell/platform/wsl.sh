#!/bin/bash
# All WSL-specific runtime concerns — functions and aliases.
# Sourced conditionally by shell/init.sh when DOTFILES_WSL=1.
# No WSL guard needed here — init.sh handles the check.

# ==============================================================================
# SSH agent bridge — OPT-IN per machine
# ==============================================================================
#
# Forward the Windows ssh-agent (e.g. Bitwarden serving the standard
# \\.\pipe\openssh-ssh-agent pipe) into WSL, so SSH keys live in the vault and
# never touch disk — one agent then serves Windows, WSL, and VS Code.
#
# Enable on a PERSONAL machine by creating the marker file:
#     touch ~/.ssh/use-windows-agent
# (A marker file, not an env var: this runs before ~/.shell.local is sourced.)
#
# WORK machines that must use local on-disk keys: leave the marker ABSENT. This
# block is skipped, SSH_AUTH_SOCK is untouched, and ssh uses the local agent /
# ~/.ssh key files. Put work-specific Host/IdentityFile blocks in
# ~/.ssh/config.local (included by ssh_config). See docs/customization.md.
if [[ -f "$HOME/.ssh/use-windows-agent" ]] && command -v wsl2-ssh-agent >/dev/null 2>&1; then
    eval "$(wsl2-ssh-agent)"
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
