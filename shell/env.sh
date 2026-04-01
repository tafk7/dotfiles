#!/bin/bash
# Static exports and PATH composition. No eval. No subshells.
# Single source of truth for everything on PATH.
#
# Sourced by:
#   - entry/profile.sh (login shells, non-interactive subshells)
#   - shell/init.sh (interactive shells)
# Safe to source multiple times — idempotency guard below.
#
# Tool init (pyenv eval, direnv hook, completions) lives in shell/tool-init.sh.

[[ -n "${_DOTFILES_ENV_LOADED:-}" ]] && return 0
_DOTFILES_ENV_LOADED=1

# ==============================================================================
# PATH Composition
# ==============================================================================

# User directories
[[ -d "$HOME/bin" ]] && PATH="$HOME/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
[[ -d "/usr/local/bin" ]] && PATH="/usr/local/bin:$PATH"

# NVM (stable symlink to active version — no nvm.sh sourcing needed)
export NVM_DIR="$HOME/.nvm"
[[ -d "$NVM_DIR/default/bin" ]] && PATH="$NVM_DIR/default/bin:$PATH"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && PATH="$PYENV_ROOT/bin:$PATH"

# Go
if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    [[ -d "$GOPATH/bin" ]] && PATH="$GOPATH/bin:$PATH"
fi

# Rust
if [[ -d "$HOME/.cargo" ]]; then
    export CARGO_HOME="$HOME/.cargo"
    [[ -d "$CARGO_HOME/bin" ]] && PATH="$CARGO_HOME/bin:$PATH"
fi

# ==============================================================================
# Tool-Specific Settings
# ==============================================================================

# Editor
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"

# Python
export PYTHONDONTWRITEBYTECODE=1
export PIP_REQUIRE_VIRTUALENV=false

# Node.js
export NODE_OPTIONS="--max-old-space-size=4096"

# Docker
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Bat
export BAT_THEME="${BAT_THEME:-gruvbox-dark}"

export PROJECTS_DIR="$HOME/projects"

# ==============================================================================
# WSL-Specific Environment
# ==============================================================================

if [[ "${DOTFILES_WSL:-0}" == "1" ]] || command -v wslpath >/dev/null 2>&1; then
    # DISPLAY: don't override if already set (WSLg sets this automatically)
    if [[ -z "${DISPLAY:-}" ]]; then
        if [[ -f /etc/resolv.conf ]] && grep -q "nameserver.*172\." /etc/resolv.conf 2>/dev/null; then
            export DISPLAY="$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf):0"
        else
            export DISPLAY=:0
        fi
    fi
    export LIBGL_ALWAYS_INDIRECT=1
    export BROWSER="wslview"
    export WSLENV="USERPROFILE/pu:APPDATA/pu"

    # Strip Windows PATH entries that shadow Linux tools
    if [[ -n "$PATH" ]]; then
        export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v -E \
            '/mnt/c/Windows/(System32/(Wbem|WindowsPowerShell|OpenSSH)|SysWOW64)' | \
            tr '\n' ':' | sed 's/:$//')
    fi

    # WIN_USER set at install time in generated/bridge.sh
    if [[ -z "${WIN_USER:-}" ]]; then
        [[ -z "${_WIN_USER_WARNED:-}" ]] && echo "Warning: WIN_USER not set — run setup.sh to configure WSL environment." >&2
        _WIN_USER_WARNED=1
    fi

    # Windows paths (derived from WIN_USER)
    if [[ -n "${WIN_USER:-}" ]]; then
        export WIN_HOME="/mnt/c/Users/$WIN_USER"
        export WIN_DESKTOP="$WIN_HOME/Desktop"
        export WIN_DOWNLOADS="$WIN_HOME/Downloads"
        export WIN_DOCUMENTS="$WIN_HOME/Documents"
        export WIN_SSH="$WIN_HOME/.ssh"
    fi
fi
