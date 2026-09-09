#!/bin/bash

_dotfiles_theme_refresh() {
    local saved_status=$? updates
    [[ -x "${DOTFILES_DIR:-}/bin/theme-switcher" ]] || return "$saved_status"
    updates="$("$DOTFILES_DIR/bin/theme-switcher" env "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" 2>/dev/null)" || return "$saved_status"
    if [[ -n "$updates" ]]; then
        eval "$updates"
        command -v _dotfiles_fzf_apply_theme >/dev/null 2>&1 && _dotfiles_fzf_apply_theme
    fi
    return "$saved_status"
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook -d precmd _dotfiles_theme_refresh 2>/dev/null || true
    add-zsh-hook precmd _dotfiles_theme_refresh
elif [[ -n "${BASH_VERSION:-}" ]]; then
    case ";${PROMPT_COMMAND:-};" in
        *';_dotfiles_theme_refresh;'*) ;;
        *) PROMPT_COMMAND="_dotfiles_theme_refresh${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
fi
