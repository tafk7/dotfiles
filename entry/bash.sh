# Bash configuration
# Owns: shell options, history, completion, prompt, bash-specific keybindings

# Load bridge (sole DOTFILES_DIR source)
[[ -f "$HOME/.config/dotfiles/env" ]] && source "$HOME/.config/dotfiles/env"

# Fallback: derive from symlink (one fallback, one place)
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
    export DOTFILES_DIR
fi

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

source "$DOTFILES_DIR/shell/init.sh"

# ==============================================================================
# Prompt — starship (unified across shells)
# ==============================================================================

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    PS1='\[\e[38;5;108m\]\u\[\e[0m\]@\[\e[38;5;214m\]\h\[\e[0m\]:\[\e[38;5;108m\]\w\[\e[0m\] \$ '
fi

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
# NVM (lazy)
# ==============================================================================

source "$DOTFILES_DIR/shell/lazy/nvm.sh"

# ==============================================================================
# Local Overrides (not tracked in git)
# ==============================================================================

[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local
