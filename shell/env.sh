#!/bin/bash
# Static exports and PATH composition. Single source of truth for
# everything on PATH.
#
# Sourced by:
#   - entry/profile.sh (login shells, non-interactive subshells)
#   - shell/init.sh (interactive shells)
# Always AFTER shell/env-runtime.sh, which holds the always-fresh exports
# (STARSHIP_CONFIG, BAT_CACHE_PATH, theme-overrides) that point at
# generated/ files and must re-evaluate on `reload`.
#
# Safe to source multiple times — guarded by _DOTFILES_ENV_LOADED below.
# `reload` (in shell/tools/general.sh) unsets the guard so guarded exports
# actually re-run after PATH/env edits.
#
# The guard is EXPORTED so child processes inherit it and skip the PATH
# composition that the parent already performed. Without this, every
# `zsh -c "cmd"` subprocess (and any other shell that re-sources this
# file) would re-prepend ~/bin, ~/.local/bin, $DOTFILES_DIR/bin, NVM,
# etc. onto the inherited PATH, producing unbounded duplication
# across nested subprocesses.
#
# Interactive-only tool init (direnv hook, completions)
# lives in shell/tool-init.sh. CWD-sensitive exports that must re-fire
# in every subprocess (notably `direnv export`) live in
# shell/env-runtime.sh, which is intentionally un-guarded.

[[ -n "${_DOTFILES_ENV_LOADED:-}" ]] && return 0
export _DOTFILES_ENV_LOADED=1

# ==============================================================================
# PATH Composition
# ==============================================================================

# User directories
[[ -d "$HOME/bin" ]] && PATH="$HOME/bin:$PATH"
[[ -d "$HOME/.local/bin" ]] && PATH="$HOME/.local/bin:$PATH"
[[ -d "/usr/local/bin" ]] && PATH="/usr/local/bin:$PATH"

# Dotfiles user commands (theme-switcher, verify, cheatsheet, replace)
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
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-nvim}"

# Python
export PYTHONDONTWRITEBYTECODE=1
export PIP_REQUIRE_VIRTUALENV=false

# Node.js
# NODE_OPTIONS is intentionally NOT set globally — forcing
# --max-old-space-size onto every node process affects small CLIs and tools
# that may mis-handle inherited options. Set it per-project (e.g. in an
# .envrc) or in ~/.shell.local if a specific tool needs a larger heap.

# Docker
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Bat / Starship / Delta defaults (themes' shell.sh overrides these)
export BAT_THEME="${BAT_THEME:-gruvbox-dark}"
export STARSHIP_PALETTE="${STARSHIP_PALETTE:-gruvbox}"
export DELTA_FEATURE="${DELTA_FEATURE:-gruvbox}"

# Note: STARSHIP_CONFIG and BAT_CACHE_PATH are set in shell/env-runtime.sh
# (the un-guarded sibling) so they re-resolve on `reload` after a theme
# switch and so subprocesses see fresh values. Don't duplicate them here.

export PROJECTS_DIR="$HOME/projects"

# Project search roots — colon-separated, like PATH. Used by `proj`,
# `fzf-project`, and `cproj`. Override per-machine via your shell rc.
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

# Note: `direnv export` lives in shell/env-runtime.sh — it must re-fire
# in every subprocess (it's CWD-sensitive), and the exported guard on
# this file would skip it here in child shells.
