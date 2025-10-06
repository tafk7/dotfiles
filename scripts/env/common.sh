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
# DOTFILES_DIR is set by install.sh and should be available
# Validate it's set to catch configuration issues early
if [[ -z "$DOTFILES_DIR" ]]; then
    echo "Warning: DOTFILES_DIR not set. Some functionality may not work." >&2
fi

# FZF configuration is handled by scripts/env/fzf.sh (sourced separately)
# This separation keeps FZF settings in one place with all preview configs

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
if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    [[ -d "$GOPATH/bin" ]] && export PATH="$GOPATH/bin:$PATH"
fi

# Rust configuration
if [[ -d "$HOME/.cargo" ]]; then
    export CARGO_HOME="$HOME/.cargo"
    [[ -d "$CARGO_HOME/bin" ]] && export PATH="$CARGO_HOME/bin:$PATH"
fi

# Local binaries
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"


# WSL-specific environment
if [[ "$IS_WSL" == "true" ]]; then
    # Display for GUI apps
    export DISPLAY=:0
    export LIBGL_ALWAYS_INDIRECT=1
    
    # Browser for WSL
    export BROWSER="wslview"
fi