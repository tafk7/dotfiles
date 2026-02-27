# ~/.profile: executed by the command interpreter for login shells.
# Owns: PATH baseline, locale, XDG, PAGER, TERM, TZ
# Tool-specific settings live in shell/env.sh (sourced by bashrc/zshrc)

# Double-source guard — zshrc sources this for non-login shells
[[ -n "$_PROFILE_LOADED" ]] && return
_PROFILE_LOADED=1

# PATH baseline — user and system bin directories
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

if [ -d "/usr/local/bin" ] ; then
    PATH="/usr/local/bin:$PATH"
fi

# Version managers — lightweight PATH-only, no eval/sourcing
# Full init (completions, switching) lives in env.sh via bashrc/zshrc.
# This ensures non-interactive processes (VS Code extensions, cron, etc.)
# find the user-managed binaries instead of falling back to system ones.

# NVM default node (stable symlink created by install-nvm.sh)
export NVM_DIR="$HOME/.nvm"
if [ -d "$NVM_DIR/default/bin" ]; then
    PATH="$NVM_DIR/default/bin:$PATH"
fi

# pyenv
if [ -d "$HOME/.pyenv/bin" ]; then
    PATH="$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH"
fi

# Locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

# Timezone
if [ -z "$TZ" ]; then
    export TZ="UTC"
fi

# XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Terminal (don't override TERM if already set — tmux sets tmux-256color)
export TERM="${TERM:-xterm-256color}"
export PAGER=less
export LESS='-F -g -i -M -R -S -w -X -z-4'

# Load shell-specific configuration
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
elif [ -n "$ZSH_VERSION" ]; then
    if [ -f "$HOME/.zshrc" ]; then
        . "$HOME/.zshrc"
    fi
fi
