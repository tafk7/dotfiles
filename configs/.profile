# .profile - Executed by the command interpreter for login shells
# This file is not read by bash if ~/.bash_profile or ~/.bash_login exists
# Part of dotfiles - https://github.com/yourusername/dotfiles

# ==============================================================================
# Path Configuration
# ==============================================================================

# Add local bin directories to PATH if they exist
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# Add cargo bin if Rust is installed
if [ -d "$HOME/.cargo/bin" ] ; then
    PATH="$HOME/.cargo/bin:$PATH"
fi

# Add go bin if Go is installed
if [ -d "$HOME/go/bin" ] ; then
    PATH="$HOME/go/bin:$PATH"
fi

# Add npm global bin if Node is installed
if [ -d "$HOME/.npm-global/bin" ] ; then
    PATH="$HOME/.npm-global/bin:$PATH"
fi

# ==============================================================================
# Environment Variables
# ==============================================================================

# Set default editor
if command -v vim >/dev/null 2>&1; then
    export EDITOR='vim'
    export VISUAL='vim'
elif command -v vi >/dev/null 2>&1; then
    export EDITOR='vi'
    export VISUAL='vi'
else
    export EDITOR='nano'
    export VISUAL='nano'
fi

# Set default pager
if command -v less >/dev/null 2>&1; then
    export PAGER='less'
    export LESS='-R'
fi

# Set language and locale
export LANG='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'

# History configuration
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups

# Development environment variables
export PYTHONDONTWRITEBYTECODE=1  # Prevent Python from writing .pyc files
export NODE_ENV=development       # Default Node environment

# ==============================================================================
# WSL Detection and Configuration
# ==============================================================================

# Detect WSL environment
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
    export IS_WSL=true
    
    # Set DISPLAY for WSLg (GUI applications)
    if [ -n "$WAYLAND_DISPLAY" ]; then
        export DISPLAY=:0
    fi
    
    # Browser for WSL
    if command -v wslview >/dev/null 2>&1; then
        export BROWSER=wslview
    fi
    
    # Windows paths
    export WIN_HOME="/mnt/c/Users/$(whoami)"
else
    export IS_WSL=false
fi

# ==============================================================================
# Dotfiles Configuration
# ==============================================================================

# Set dotfiles directory if not already set
if [ -z "$DOTFILES_DIR" ]; then
    # Try to find dotfiles directory
    if [ -d "$HOME/dotfiles" ]; then
        export DOTFILES_DIR="$HOME/dotfiles"
    elif [ -d "$HOME/.dotfiles" ]; then
        export DOTFILES_DIR="$HOME/.dotfiles"
    fi
fi

# ==============================================================================
# XDG Base Directory Specification
# ==============================================================================

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Create XDG directories if they don't exist
[ ! -d "$XDG_CONFIG_HOME" ] && mkdir -p "$XDG_CONFIG_HOME"
[ ! -d "$XDG_CACHE_HOME" ] && mkdir -p "$XDG_CACHE_HOME"
[ ! -d "$XDG_DATA_HOME" ] && mkdir -p "$XDG_DATA_HOME"
[ ! -d "$XDG_STATE_HOME" ] && mkdir -p "$XDG_STATE_HOME"

# ==============================================================================
# FZF Configuration
# ==============================================================================

# Set FZF defaults if fzf is installed
if command -v fzf >/dev/null 2>&1; then
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
    
    # Use fd for fzf if available
    if command -v fd >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    # Use ripgrep if fd is not available
    elif command -v rg >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    fi
fi

# ==============================================================================
# Terminal Configuration
# ==============================================================================

# Enable true color support if available
if [ -n "$TMUX" ]; then
    export TERM="screen-256color"
else
    case "$TERM" in
        xterm*) export TERM="xterm-256color" ;;
    esac
fi

# ==============================================================================
# Security Settings
# ==============================================================================

# Set secure umask
umask 022

# ==============================================================================
# Shell-Specific Configuration
# ==============================================================================

# If running bash, source .bashrc if it exists
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# If running zsh, source .zshrc if it exists
if [ -n "$ZSH_VERSION" ]; then
    if [ -f "$HOME/.zshrc" ]; then
        . "$HOME/.zshrc"
    fi
fi

# ==============================================================================
# Local Configuration
# ==============================================================================

# Source local profile if it exists
if [ -f "$HOME/.profile.local" ]; then
    . "$HOME/.profile.local"
fi