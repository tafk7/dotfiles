# Bash configuration
# Owns: shell options, history, completion, bash-specific settings

# Derive DOTFILES_DIR from symlink — always works regardless of install state
DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
export DOTFILES_DIR
[[ -f "$DOTFILES_DIR/generated/bridge.sh" ]] && source "$DOTFILES_DIR/generated/bridge.sh"

# Non-interactive: just set PATH baseline and stop
if [[ $- != *i* ]]; then
    [[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
    return
fi

# PATH baseline for non-login interactive (VS Code terminals)
[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"

# ==============================================================================
# Shell Options
# ==============================================================================

shopt -s histappend checkwinsize globstar extglob

# Completion
if ! shopt -oq posix; then
    [[ -f /usr/share/bash-completion/bash_completion ]] && \
        . /usr/share/bash-completion/bash_completion
fi
complete -cf sudo man

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
# Shared initialization sequence
# ==============================================================================

SHELL_NAME=bash
source "$DOTFILES_DIR/shell/init.sh"
