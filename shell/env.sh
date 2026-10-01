#!/bin/bash
# Static exports and PATH composition: the single source of truth for PATH.
# Sourced after shell/env-runtime.sh by entry/profile.sh and shell/init.sh.
#
# The guard is exported so child shells inherit the composed environment
# instead of re-prepending the same directories at every nesting level.
# `reload` unsets it to force recomputation. CWD-sensitive exports live in
# shell/env-runtime.sh; interactive tool init lives in shell/tool-init.sh.

[[ -n "${_DOTFILES_ENV_LOADED:-}" ]] && return 0
export _DOTFILES_ENV_LOADED=1

# ==============================================================================
# PATH Composition
# ==============================================================================

# opencode's self-update reruns its installer, which appends a PATH line to
# ~/.bashrc (a repo symlink) unless this directory is already on PATH. The
# ~/.local/bin launcher still resolves first.
[[ -d "$HOME/.opencode/bin" ]] && PATH="$HOME/.opencode/bin:$PATH"

# User directories
[[ -d "$HOME/bin" ]] && PATH="$HOME/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
[[ -d "/usr/local/bin" ]] && PATH="/usr/local/bin:$PATH"

# Dotfiles user commands
[[ -d "${DOTFILES_DIR:-}/bin" ]] && PATH="$DOTFILES_DIR/bin:$PATH"

# NVM (stable symlink to active version — no nvm.sh sourcing needed)
export NVM_DIR="$HOME/.nvm"
[[ -d "$NVM_DIR/default/bin" ]] && PATH="$NVM_DIR/default/bin:$PATH"

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
if [[ -z "${EDITOR:-}" ]]; then
    for _dotfiles_editor in nvim vim nano vi; do
        if command -v "$_dotfiles_editor" >/dev/null 2>&1; then
            EDITOR="$_dotfiles_editor"
            break
        fi
    done
    unset _dotfiles_editor
fi
export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-$EDITOR}"

# Python
export PYTHONDONTWRITEBYTECODE=1
export PIP_REQUIRE_VIRTUALENV=false
export RIPGREP_CONFIG_PATH="${RIPGREP_CONFIG_PATH:-$HOME/.ripgreprc}"

# Node.js
# NODE_OPTIONS is deliberately not set: every node process would inherit it,
# including small CLIs. Set it per project in .envrc if a tool needs it.

# Docker
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Theme-specific variables are deliberately absent from Layer 0. Interactive
# startup adds them only when the optional theme feature is enabled.

# Project search roots for proj, fzf-project, and cproj (colon-separated).
export PROJECTS_DIRS="${PROJECTS_DIRS:-$HOME/projects:$HOME/work:$HOME/dev:$HOME/code:$HOME/src}"

# ==============================================================================
# WSL-Specific Environment
# ==============================================================================

if [[ "${DOTFILES_WSL:-0}" == "1" ]] || command -v wslpath >/dev/null 2>&1; then
    # DISPLAY: don't override if already set (WSLg sets this automatically)
    if [[ -z "${DISPLAY:-}" ]]; then
        if [[ -f /etc/resolv.conf ]] && grep -q "nameserver.*172\." /etc/resolv.conf 2>/dev/null; then
            DISPLAY="$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf):0"
            export DISPLAY
        else
            export DISPLAY=:0
        fi
    fi
    export LIBGL_ALWAYS_INDIRECT=1
    export BROWSER="wslview"
    export WSLENV="USERPROFILE/pu:APPDATA/pu"

    # Strip Windows PATH entries that shadow Linux tools
    if [[ -n "$PATH" ]]; then
        PATH=$(echo "$PATH" | tr ':' '\n' | grep -v -E \
            '/mnt/c/Windows/(System32/(Wbem|WindowsPowerShell|OpenSSH)|SysWOW64)' | \
            tr '\n' ':' | sed 's/:$//')
        export PATH
    fi

    # WIN_USER is recorded as data-only machine state at install time.
    if [[ -z "${WIN_USER:-}" ]]; then
        _dotfiles_preferences="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/preferences.tsv"
        if [[ -r "$_dotfiles_preferences" ]]; then
            WIN_USER="$(awk -F '\t' '$1 == "machine.win_user" { print $2; exit }' "$_dotfiles_preferences")"
            [[ -z "$WIN_USER" ]] || export WIN_USER
        fi
        unset _dotfiles_preferences
        if [[ -z "${WIN_USER:-}" ]]; then
            [[ -z "${_WIN_USER_WARNED:-}" ]] && echo "Warning: WIN_USER not set — run setup.sh to configure WSL environment." >&2
            _WIN_USER_WARNED=1
        fi
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
