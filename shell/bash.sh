# Bash configuration
# Owns: shell options, history, completion, prompt, bash-specific keybindings

# PATH baseline — ~/.profile handles this for login shells, but VS Code and other
# terminals launch bash as non-login (skipping ~/.profile). Profile has a source
# guard so this is safe in both login and non-login shells.
# _BASHRC_LOADED prevents double-sourcing when profile sources bashrc back.
if [[ -z "$_BASHRC_LOADED" ]]; then
    [[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
fi
_BASHRC_LOADED=1

# Load install-time environment (written by setup.sh)
[[ -f "$HOME/.config/dotfiles/env" ]] && source "$HOME/.config/dotfiles/env"

# Fallback: derive DOTFILES_DIR from symlink if env file is missing
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
    export DOTFILES_DIR
fi

# Non-interactive: stop here
[[ $- != *i* ]] && return

# ==============================================================================
# Shell Options
# ==============================================================================

shopt -s histappend checkwinsize globstar extglob

# Completion
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

complete -cf sudo
complete -cf man

# ==============================================================================
# History
# ==============================================================================

HISTFILE=~/.bash_history
HISTSIZE=${BASH_HIST_SIZE:-50000}
HISTFILESIZE=$((HISTSIZE * 2))
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%F %T "
HISTIGNORE=""

[[ "$PROMPT_COMMAND" != *"history -a"* ]] && \
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a"

# ==============================================================================
# Shared sequence (env → theme → fzf → functions → aliases)
# ==============================================================================

source "$DOTFILES_DIR/shell/shared.sh"

# ==============================================================================
# FZF Key Bindings (bash-specific)
# ==============================================================================

if command -v fzf >/dev/null 2>&1; then
    [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] && \
        source /usr/share/doc/fzf/examples/key-bindings.bash
    [[ -f /usr/share/doc/fzf/examples/completion.bash ]] && \
        source /usr/share/doc/fzf/examples/completion.bash
fi

# ==============================================================================
# Prompt
# ==============================================================================

# Git-aware prompt (disable with: export BASH_NO_GIT_PROMPT=1)
git_prompt() {
    [[ -n "$BASH_NO_GIT_PROMPT" ]] && return

    local git_status git_branch
    if git_branch=$(timeout 0.1s git symbolic-ref --short HEAD 2>/dev/null); then
        git_status=$(timeout 0.2s git status --porcelain 2>/dev/null)
        if [[ -n $git_status ]]; then
            echo " ${PROMPT_COLOR_GIT_DIRTY}($git_branch*)${PROMPT_COLOR_RESET}"
        else
            echo " ${PROMPT_COLOR_GIT_CLEAN}($git_branch)${PROMPT_COLOR_RESET}"
        fi
    fi
}

# Default prompt colors (overridden by theme if loaded)
if [[ -z "$PROMPT_COLOR_USER" ]]; then
    export PROMPT_COLOR_USER='\[\e[38;5;108m\]'
    export PROMPT_COLOR_HOST='\[\e[38;5;214m\]'
    export PROMPT_COLOR_PATH='\[\e[38;5;108m\]'
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;142m\]'
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;167m\]'
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;142m\]'
    export PROMPT_COLOR_ERROR='\[\e[38;5;167m\]'
    export PROMPT_COLOR_RESET='\[\e[0m\]'
fi

set_prompt() {
    local exit_code=$?
    local prompt_symbol

    if [[ $exit_code -ne 0 ]]; then
        prompt_symbol="${PROMPT_COLOR_ERROR}✗${PROMPT_COLOR_RESET}"
    else
        prompt_symbol="${PROMPT_COLOR_SUCCESS}✓${PROMPT_COLOR_RESET}"
    fi

    PS1="${PROMPT_COLOR_USER}\u${PROMPT_COLOR_RESET}@${PROMPT_COLOR_HOST}\h${PROMPT_COLOR_RESET}:${PROMPT_COLOR_PATH}\w${PROMPT_COLOR_RESET}"
    PS1+="$(git_prompt)"
    PS1+=" ${prompt_symbol} "
}

[[ "$PROMPT_COMMAND" != *"set_prompt"* ]] && \
    PROMPT_COMMAND="set_prompt; $PROMPT_COMMAND"

# ==============================================================================
# NVM (lazy)
# ==============================================================================

source "$DOTFILES_DIR/shell/nvm-lazy.sh"

# ==============================================================================
# Local Overrides (not tracked in git)
# ==============================================================================

[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
