#!/bin/bash
# WSL-specific environment variables
# Only loaded when running in Windows Subsystem for Linux

# Only load these variables on WSL systems
if ! command -v wslpath >/dev/null 2>&1; then
    return 0
fi

# Windows paths - using $USER instead of $(whoami) for security
export WIN_HOME="/mnt/c/Users/$USER"
export WIN_DESKTOP="$WIN_HOME/Desktop"
export WIN_DOWNLOADS="$WIN_HOME/Downloads"
export WIN_DOCUMENTS="$WIN_HOME/Documents"
export WIN_SSH="$WIN_HOME/.ssh"