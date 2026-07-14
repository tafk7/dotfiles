# shellcheck shell=bash
# Bash configuration
# Owns: shell options, history, completion, bash-specific settings

# Establish DOTFILES_DIR. Symlink derivation locates the repo for a fresh clone,
# but a bind-mount/copy (containers, WSL, rsync) flattens the symlink so
# readlink resolves to the file itself → a wrong dir. generated/bridge.sh holds
# the install-time truth, so let it OVERRIDE the guess: try the derived path,
# then the conventional location; bridge.sh's `export` wins either way.
DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
export DOTFILES_DIR
for _bridge in "$DOTFILES_DIR/generated/bridge.sh" "$HOME/dotfiles/generated/bridge.sh"; do
    [[ -f "$_bridge" ]] && { source "$_bridge"; break; }
done
unset _bridge

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
