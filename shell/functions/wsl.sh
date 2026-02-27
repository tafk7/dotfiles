#!/bin/bash
# WSL-specific functions for Windows integration

# Only load on WSL systems
command -v wslpath >/dev/null 2>&1 || return 0

# Import SSH keys from Windows — single consolidated definition
# Uses $WIN_USER from env file, does NOT call cmd.exe to re-derive
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
