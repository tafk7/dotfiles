#!/bin/bash
# Shell environment configuration

# ==============================================================================
# Common Environment Variables
# ==============================================================================

# Node Version Manager
export NVM_DIR="$HOME/.nvm"

# Python Version Manager (pyenv)
export PYENV_ROOT="$HOME/.pyenv"
# Initialize pyenv if installed
if [[ -d "$PYENV_ROOT" ]]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path 2>/dev/null || true)"
    eval "$(pyenv init - 2>/dev/null || true)"
fi

# direnv - auto-load .envrc files
if command -v direnv >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(direnv hook bash)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(direnv hook zsh)"
    fi
fi

# uv - shell completion
if command -v uv >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(uv generate-shell-completion bash 2>/dev/null || true)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(uv generate-shell-completion zsh 2>/dev/null || true)"
    fi
fi

# poetry - shell completion
if command -v poetry >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(poetry completions bash 2>/dev/null || true)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(poetry completions zsh 2>/dev/null || true)"
    fi
fi

# Theme configuration
# Read theme from persistent storage if it exists
THEME_FILE="$HOME/.config/dotfiles/current-theme"
if [[ -f "$THEME_FILE" ]]; then
    export DOTFILES_THEME=$(cat "$THEME_FILE" 2>/dev/null)
fi

# Path constants
export PROJECTS_DIR="$HOME/projects"
# DOTFILES_DIR is set by setup.sh and should be available
# Validate it's set to catch configuration issues early
if [[ -z "$DOTFILES_DIR" ]]; then
    echo "Warning: DOTFILES_DIR not set. Some functionality may not work." >&2
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

# ==============================================================================
# FZF Configuration
# ==============================================================================

# Default options - simple and fast
export FZF_DEFAULT_OPTS="
    --height 60%
    --layout=reverse
    --border=rounded
    --preview-window=right:60%:wrap
    --bind 'ctrl-/:change-preview-window(down|hidden|)'
    --bind 'ctrl-p:toggle-preview'"

# Use fd/fdfind if available for better performance
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
fi

# Ctrl-T: File preview — glow for Markdown, bat for everything else
if command -v glow >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview '[[ {} == *.md ]] && glow -s dark --width \$FZF_PREVIEW_COLUMNS {} || bat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'"
elif command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'bat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'"
elif command -v batcat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'batcat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'"
else
    export FZF_CTRL_T_OPTS="
        --preview 'cat {}'
        --bind 'ctrl-p:toggle-preview'"
fi

# Alt-C: Directory preview
if command -v eza >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'eza --tree --color=always --level=2 {} | head -200'
        --bind 'ctrl-p:toggle-preview'"
elif command -v tree >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'tree -C {} | head -200'
        --bind 'ctrl-p:toggle-preview'"
fi

# Ctrl-R: Better history search
export FZF_CTRL_R_OPTS="
    --preview 'echo {}'
    --preview-window down:3:hidden:wrap
    --bind 'ctrl-p:toggle-preview'
    --exact"

# Integration with zoxide
if command -v zoxide >/dev/null 2>&1; then
    alias zi='zoxide query -i'
fi

# ==============================================================================
# WSL-Specific Environment
# ==============================================================================

if command -v wslpath >/dev/null 2>&1; then
    # Display for GUI apps
    export DISPLAY=:0
    export LIBGL_ALWAYS_INDIRECT=1

    # Browser for WSL
    export BROWSER="wslview"

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
fi
