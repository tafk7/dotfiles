#!/bin/bash
# Tool initialization and tool-specific environment
# Owns: version managers, tool PATH extensions, EDITOR, tool-specific settings, WSL env

# Validate DOTFILES_DIR — set by ~/.config/dotfiles/env, sourced before this file
if [[ -z "$DOTFILES_DIR" ]]; then
    echo "Warning: DOTFILES_DIR not set. Some functionality may not work." >&2
fi

# ==============================================================================
# Tool Initialization
# ==============================================================================

# Node Version Manager
export NVM_DIR="$HOME/.nvm"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
if [[ -d "$PYENV_ROOT" ]]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init --path 2>/dev/null || true)"
    eval "$(pyenv init - 2>/dev/null || true)"
fi

# direnv
if command -v direnv >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(direnv hook bash)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(direnv hook zsh)"
    fi
fi

# uv completion
if command -v uv >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(uv generate-shell-completion bash 2>/dev/null || true)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(uv generate-shell-completion zsh 2>/dev/null || true)"
    fi
fi

# poetry completion
if command -v poetry >/dev/null 2>&1; then
    if [[ -n "${BASH_VERSION:-}" ]]; then
        eval "$(poetry completions bash 2>/dev/null || true)"
    elif [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(poetry completions zsh 2>/dev/null || true)"
    fi
fi

# ==============================================================================
# Tool-Specific PATH Extensions
# ==============================================================================

# Go
if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    [[ -d "$GOPATH/bin" ]] && export PATH="$GOPATH/bin:$PATH"
fi

# Rust
if [[ -d "$HOME/.cargo" ]]; then
    export CARGO_HOME="$HOME/.cargo"
    [[ -d "$CARGO_HOME/bin" ]] && export PATH="$CARGO_HOME/bin:$PATH"
fi

# ==============================================================================
# Tool-Specific Settings
# ==============================================================================

# Editor — prefer neovim
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="nvim"
    export VISUAL="nvim"
else
    export EDITOR="vim"
    export VISUAL="vim"
fi

# Python
export PYTHONDONTWRITEBYTECODE=1
export PIP_REQUIRE_VIRTUALENV=false

# Node.js
if command -v node >/dev/null 2>&1; then
    export NODE_OPTIONS="--max-old-space-size=4096"
fi

# Docker
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Bat
if command -v bat >/dev/null 2>&1 || command -v batcat >/dev/null 2>&1; then
    export BAT_THEME="${BAT_THEME:-gruvbox-dark}"
fi

# Theme name (read from persistent storage)
THEME_FILE="$HOME/.config/dotfiles/current-theme"
if [[ -f "$THEME_FILE" ]]; then
    export DOTFILES_THEME=$(cat "$THEME_FILE" 2>/dev/null)
fi

export PROJECTS_DIR="$HOME/projects"

# ==============================================================================
# WSL-Specific Environment
# ==============================================================================

if command -v wslpath >/dev/null 2>&1; then
    export DISPLAY=:0
    export LIBGL_ALWAYS_INDIRECT=1
    export BROWSER="wslview"
    export WSLENV="USERPROFILE/pu:APPDATA/pu"

    # Strip Windows PATH entries that shadow Linux tools
    # Keeps: System32 (clip.exe, wsl.exe), VS Code, Program Files, AppData
    if [[ -n "$PATH" ]]; then
        export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v -E \
            '/mnt/c/Windows/(System32/(Wbem|WindowsPowerShell|OpenSSH)|SysWOW64)' | \
            tr '\n' ':' | sed 's/:$//')
    fi

    # Windows username — set at install time by setup.sh, fallback to cmd.exe
    if [[ -z "$WIN_USER" ]]; then
        WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
        if [[ -z "$WIN_USER" ]] || [[ "$WIN_USER" == "SYSTEM" ]]; then
            WIN_USER="$USER"
        fi
    fi

    # Windows paths (derived from WIN_USER)
    export WIN_HOME="/mnt/c/Users/$WIN_USER"
    export WIN_DESKTOP="$WIN_HOME/Desktop"
    export WIN_DOWNLOADS="$WIN_HOME/Downloads"
    export WIN_DOCUMENTS="$WIN_HOME/Documents"
    export WIN_SSH="$WIN_HOME/.ssh"
fi
