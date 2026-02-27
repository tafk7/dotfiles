#!/bin/bash
# All WSL-specific runtime concerns — functions and aliases.
# Sourced conditionally by shell/init.sh when DOTFILES_WSL=1.
# No WSL guard needed here — init.sh handles the check.

# ==============================================================================
# Functions
# ==============================================================================

# Import SSH keys from Windows
import_windows_ssh_keys() {
    local win_user="${WIN_USER:-}"
    if [[ -z "$win_user" ]]; then
        echo "WIN_USER not set — run setup.sh to configure WSL environment."
        return 0
    fi

    local windows_ssh_dir="/mnt/c/Users/$win_user/.ssh"

    if [[ ! -d "$windows_ssh_dir" ]]; then
        echo "No Windows SSH directory found at $windows_ssh_dir"
        return 0
    fi

    echo "Importing SSH keys from Windows ($windows_ssh_dir)..."

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    for key_file in "$windows_ssh_dir"/*; do
        if [[ -f "$key_file" ]]; then
            local filename=$(basename "$key_file")
            local target="$ssh_dir/$filename"

            cp "$key_file" "$target"

            if [[ "$filename" == *.pub ]]; then
                chmod 644 "$target"
            else
                chmod 600 "$target"
            fi

            echo "  Imported: $filename"
        fi
    done

    echo "SSH key import completed."
}

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
    local winpath=$(wslpath -w "$(pwd)")
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

# PowerShell
if [[ -x "/mnt/c/Program Files/PowerShell/7/pwsh.exe" ]]; then
    alias pwsh='/mnt/c/Program\ Files/PowerShell/7/pwsh.exe'
else
    alias pwsh='powershell.exe'
fi

# File operations
alias open='explorer'
alias cwd='pwd | clip.exe'

# Path conversion
alias wpath='wslpath -w'
alias lpath='wslpath -u'

# SSH import
alias sync-ssh='import_windows_ssh_keys'
