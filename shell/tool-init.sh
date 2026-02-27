#!/bin/bash
# Interactive tool initialization. All eval calls live here.
# Sourced only in interactive shells by shell/init.sh.

# pyenv
if [[ -d "$PYENV_ROOT" ]]; then
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

# uv completion (bash only — zsh completions loaded after compinit in zshrc)
if command -v uv >/dev/null 2>&1 && [[ -n "${BASH_VERSION:-}" ]]; then
    eval "$(uv generate-shell-completion bash 2>/dev/null || true)"
fi

# poetry completion (bash only — zsh completions loaded after compinit in zshrc)
if command -v poetry >/dev/null 2>&1 && [[ -n "${BASH_VERSION:-}" ]]; then
    eval "$(poetry completions bash 2>/dev/null || true)"
fi

# Nix (multi-user Determinate Systems install)
_NIX_PROFILE="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
if [[ -f "$_NIX_PROFILE" ]] && ! command -v nix >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    . "$_NIX_PROFILE"
fi
unset _NIX_PROFILE
