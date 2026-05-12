#!/bin/bash
# Static exports and PATH composition. Single source of truth for
# everything on PATH.
#
# Sourced by:
#   - entry/profile.sh (login shells, non-interactive subshells)
#   - shell/init.sh (interactive shells)
# Safe to source multiple times — idempotency guard below.
#
# Interactive-only tool init (pyenv eval, direnv hook, completions)
# lives in shell/tool-init.sh. The one exception is the direnv export
# at the bottom of this file: non-interactive subprocesses (Claude
# Code's `bash -c`, scripts) need .envrc activation too, and the
# PROMPT_COMMAND-based hook only fires for interactive shells.

# ==============================================================================
# Always-evaluate exports — these point at generated files that may be
# created/updated AFTER env.sh first runs (e.g., `theme-switcher` → `reload`).
# Putting them above the idempotency guard ensures `reload` picks up new
# generated artifacts instead of cached-empty values from the first sourcing.
# ==============================================================================

if [[ -n "${DOTFILES_DIR:-}" ]]; then
    if [[ -f "$DOTFILES_DIR/generated/starship.toml" ]]; then
        export STARSHIP_CONFIG="$DOTFILES_DIR/generated/starship.toml"
    elif [[ -f "$DOTFILES_DIR/configs/starship.toml" ]] \
         && ! grep -q '__DOTFILES_PALETTE__' "$DOTFILES_DIR/configs/starship.toml" 2>/dev/null; then
        # Only fall back to the base config if it doesn't contain the
        # placeholder marker (would otherwise cause starship warnings).
        export STARSHIP_CONFIG="$DOTFILES_DIR/configs/starship.toml"
    fi

    if [[ -d "$DOTFILES_DIR/generated/bat/cache" ]]; then
        export BAT_CACHE_PATH="$DOTFILES_DIR/generated/bat/cache"
    fi

    # Per-component theme overrides — sourced after generated/theme.sh emits
    # the global DOTFILES_THEME, so DOTFILES_THEME_<GROUP|SURFACE>=... overrides
    # the global default. Cascade applied at apply-time by bin/theme-switcher.
    # Read by lib/theme-resolve.sh and consumed by tools (BAT_THEME etc.) that
    # generated/theme.sh emits per-surface based on the cascade.
    [[ -f "$DOTFILES_DIR/generated/theme-overrides.sh" ]] \
        && source "$DOTFILES_DIR/generated/theme-overrides.sh"
fi

[[ -n "${_DOTFILES_ENV_LOADED:-}" ]] && return 0
_DOTFILES_ENV_LOADED=1

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

# Bat / Starship / Delta defaults (themes' shell.sh overrides these)
export BAT_THEME="${BAT_THEME:-gruvbox-dark}"
export STARSHIP_PALETTE="${STARSHIP_PALETTE:-gruvbox}"
export DELTA_FEATURE="${DELTA_FEATURE:-gruvbox}"

# Note: STARSHIP_CONFIG and BAT_CACHE_PATH are set above the idempotency
# guard at the top of this file so they re-resolve on `reload` after a
# theme switch. Don't duplicate them here.

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

# ==============================================================================
# direnv .envrc activation (non-interactive shells)
# ==============================================================================
#
# `direnv hook` only fires before each interactive prompt, so non-
# interactive subprocesses (Claude Code's `bash -c`, scripts) never get
# their project venv activated. `direnv export <shell>` is the standalone
# equivalent — walks up from $PWD, honors the shared allow-list, and
# emits the .envrc's exports immediately. Safe no-op when no .envrc
# applies. `|| true` avoids aborting startup under `set -e` if an
# .envrc errors. Quiet log format keeps Bash-tool output clean.
#
# Shell-aware: zsh and bash use different export syntax (zsh's `typeset`
# vs bash's `declare`/plain assignment); using the wrong one silently
# leaks malformed quoting into the parent shell. Detect via the version
# vars each shell sets natively. Default to bash for POSIX `sh`.
#
# Interactive shells still get the hook from tool-init.sh on top —
# that handles the `cd into another project` case mid-session.
if command -v direnv >/dev/null 2>&1; then
    export DIRENV_LOG_FORMAT=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(direnv export zsh 2>/dev/null)" || true
    else
        eval "$(direnv export bash 2>/dev/null)" || true
    fi
fi
