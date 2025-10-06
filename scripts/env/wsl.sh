#!/bin/bash
# WSL-specific environment variables
# Only loaded when running in Windows Subsystem for Linux

# Only load these variables on WSL systems
if ! command -v wslpath >/dev/null 2>&1; then
    return 0
fi

# Get Windows username (may differ from Linux $USER)
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
if [[ -z "$WIN_USER" ]] || [[ "$WIN_USER" == "SYSTEM" ]]; then
    WIN_USER="$USER"  # Fallback to Linux username
fi

# Windows paths
export WIN_HOME="/mnt/c/Users/$WIN_USER"
export WIN_DESKTOP="$WIN_HOME/Desktop"
export WIN_DOWNLOADS="$WIN_HOME/Downloads"
export WIN_DOCUMENTS="$WIN_HOME/Documents"
export WIN_SSH="$WIN_HOME/.ssh"