#!/bin/bash
# WSL-specific functions for Windows integration

# Only load these functions on WSL systems
if ! command -v wslpath >/dev/null 2>&1; then
    return 0
fi

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