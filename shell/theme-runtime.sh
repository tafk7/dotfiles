#!/bin/bash

# Read only the freshness inputs here, using shell builtins. Changed or
# unfamiliar state still goes through the complete resolver and validation.
# No cached mtime or polling interval: global theme and tmux context changes
# must be visible at the very next prompt.
_dotfiles_theme_unchanged() {
    local state_dir="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
    local key value extra schema generation="" enabled=1 detected rest signature
    local preferences="${DOTFILES_PREFERENCES_FILE:-$state_dir/preferences.tsv}"
    local state="${DOTFILES_THEME_STATE_FILE:-$state_dir/theme.tsv}"
    if [[ -f "$preferences" ]]; then
        {
            IFS= read -r schema || return 1
            [[ "$schema" == $'schema\t1' ]] || return 1
            while IFS=$'\t' read -r key value extra; do
                [[ -n "$value" && -z "$extra" && "$key" =~ ^[A-Za-z0-9._/@:+-]+$ ]] || return 1
                if [[ "$key" == feature.theme ]]; then
                    enabled=1
                    [[ "$value" != disabled ]] || enabled=0
                fi
            done
        } < "$preferences"
    fi
    if [[ "$enabled" == 0 ]]; then
        [[ "${DOTFILES_THEME_ENABLED:-1}" == 0 && -z "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" ]]
        return
    fi
    [[ "${DOTFILES_THEME_ENABLED:-1}" != 0 && -n "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" && -r "$state" ]] || return 1
    {
        IFS= read -r schema || return 1
        [[ "$schema" == $'schema\t1' ]] || return 1
        while IFS=$'\t' read -r key value extra; do
            [[ -n "$value" && -z "$extra" && "$key" =~ ^[A-Za-z0-9._/@:+-]+$ ]] || return 1
            [[ "$key" != generation ]] || generation="$value"
        done
    } < "$state"
    [[ -n "$generation" ]] || return 1
    signature="$generation:::"
    if [[ -n "${TMUX:-}" ]]; then
        local -a server=()
        [[ -z "${DOTFILES_TMUX_SERVER:-}" ]] || server=(-L "$DOTFILES_TMUX_SERVER")
        detected="$(command tmux "${server[@]}" display-message -p '#{session_id} #{window_id} #{@dotfiles_theme_generation}' 2>/dev/null)" || return 1
        [[ "$detected" == *' '*' '* ]] || return 1
        rest="${detected#* }"
        signature="$generation:${detected##* }:${detected%% *}:${rest%% *}"
    fi
    [[ "$signature" == "$DOTFILES_THEME_CONTEXT_SIGNATURE" ]]
}

_dotfiles_theme_refresh() {
    local saved_status=$?
    [[ -x "${DOTFILES_DIR:-}/bin/theme-switcher" ]] || return "$saved_status"
    _dotfiles_theme_unchanged && return "$saved_status"
    # The adapter also clears stale exports when the feature is disabled.
    source "$DOTFILES_DIR/shell/interactive/theme-env.sh"
    unset _DOTFILES_THEME_ACTIVE
    command -v _dotfiles_fzf_apply_theme >/dev/null 2>&1 && _dotfiles_fzf_apply_theme
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
