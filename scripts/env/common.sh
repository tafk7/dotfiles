#!/bin/bash
# Common environment variables and settings
# Sourced by both bashrc and zshrc

# WSL environment detection is handled by lib/core.sh
# IS_WSL variable is exported by the installer after running detect_environment()

# Node Version Manager
export NVM_DIR="$HOME/.nvm"

# Theme configuration
# Read theme from persistent storage if it exists
THEME_FILE="$HOME/.config/dotfiles/current-theme"
if [[ -f "$THEME_FILE" ]]; then
    export DOTFILES_THEME=$(cat "$THEME_FILE" 2>/dev/null)
fi

# Path constants
export PROJECTS_DIR="$HOME/projects"
# DOTFILES_DIR is set by install.sh - don't hardcode it here

# FZF configuration (theme-aware)
if command -v fzf >/dev/null 2>&1; then
    # Default FZF options (can be overridden by themes)
    export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
    
    # Use fd/fdfind if available for better performance
    if command -v fdfind >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    elif command -v fd >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    fi
    
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# Bat configuration (theme-aware)
if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
    export BAT_THEME="${BAT_THEME:-gruvbox-dark}"
fi

# Editor preferences - prefer neovim, fallback to vim
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="nvim"
    export VISUAL="nvim"
else
    export EDITOR="vim"
    export VISUAL="vim"
fi

# Python configuration
export PYTHONDONTWRITEBYTECODE=1  # Prevent .pyc files

# Go configuration
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Rust configuration
export CARGO_HOME="$HOME/.cargo"
export PATH="$CARGO_HOME/bin:$PATH"

# Local binaries
export PATH="$HOME/.local/bin:$PATH"

# NPM global packages (if npm is installed)
if command -v npm >/dev/null 2>&1; then
    export PATH="$HOME/.npm-global/bin:$PATH"
fi

# WSL-specific environment
if [[ "$IS_WSL" == "true" ]]; then
    # Display for GUI apps
    export DISPLAY=:0
    export LIBGL_ALWAYS_INDIRECT=1
    
    # Browser for WSL
    export BROWSER="wslview"
fi