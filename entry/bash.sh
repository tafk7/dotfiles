# shellcheck shell=bash
# Bash configuration
# Owns: shell options, history, completion, bash-specific settings

# Locate the checkout through the symlink. A flattened copy or bind mount
# defeats that, so fall back to the recorded install path. generated/bridge.sh
# is legacy, read-only compatibility.
DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
if [[ ! -f "$DOTFILES_DIR/shell/env.sh" ]]; then
    _dotfiles_path_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install-path"
    if [[ -r "$_dotfiles_path_file" ]]; then
        IFS= read -r DOTFILES_DIR < "$_dotfiles_path_file"
    else
        DOTFILES_DIR="$HOME/dev/dotfiles"
    fi
    unset _dotfiles_path_file
fi
export DOTFILES_DIR
_bridge="$DOTFILES_DIR/generated/bridge.sh"
[[ -f "$_bridge" ]] && source "$_bridge"
unset _bridge

# Non-interactive: Layer 0 only. This is the agent shell: harnesses run
# `bash -lc` per command or snapshot a non-interactive login shell, and both
# arrive here through ~/.bash_profile.
if [[ $- != *i* ]]; then
    [[ -f "$HOME/.profile" ]] && source "$HOME/.profile"

    # Remove only the private helper Layer 0 itself introduced. Externally
    # supplied functions are owned by the caller and must survive startup.
    unset -f _dotfiles_dedupe_path 2>/dev/null || true

    return
fi

# Non-login interactive shells (e.g. VS Code terminals) still need Layer 0.
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

# ==============================================================================
# Key Bindings
# ==============================================================================

bind '"\C-h": backward-kill-word' # Ctrl+Backspace (Backspace remains DEL)
bind '"\e[3;5~": kill-word'       # Ctrl+Delete
bind '"\e\C-h": backward-kill-line' # Alt+Backspace (BS encoding)
bind '"\e\C-?": backward-kill-line' # Alt+Backspace (DEL encoding)
bind '"\e[3;3~": kill-line'          # Alt+Delete

# Shift means the removed range is also published to tmux's shared buffer.
# Windows Terminal transports these chords as virtual F13-F16 sequences.
_tafk_cut_backward_word() {
    local line="$READLINE_LINE" point=$READLINE_POINT start char cut
    start=$point

    while (( start > 0 )); do
        char=${line:start-1:1}
        [[ $char =~ [[:alnum:]_] ]] && break
        ((start--))
    done
    while (( start > 0 )); do
        char=${line:start-1:1}
        [[ $char =~ [[:alnum:]_] ]] || break
        ((start--))
    done

    cut=${line:start:point-start}
    [[ -n $cut ]] || return 0
    READLINE_LINE=${line:0:start}${line:point}
    READLINE_POINT=$start
    _tafk_tmux_buffer_set "$cut"
}

_tafk_cut_forward_word() {
    local line="$READLINE_LINE" point=$READLINE_POINT end=${#READLINE_LINE} char cut
    end=$point

    while (( end < ${#line} )); do
        char=${line:end:1}
        [[ $char =~ [[:alnum:]_] ]] && break
        ((end++))
    done
    while (( end < ${#line} )); do
        char=${line:end:1}
        [[ $char =~ [[:alnum:]_] ]] || break
        ((end++))
    done

    cut=${line:point:end-point}
    [[ -n $cut ]] || return 0
    READLINE_LINE=${line:0:point}${line:end}
    READLINE_POINT=$point
    _tafk_tmux_buffer_set "$cut"
}

_tafk_cut_backward_line() {
    local line="$READLINE_LINE" point=$READLINE_POINT cut=${READLINE_LINE:0:READLINE_POINT}
    [[ -n $cut ]] || return 0
    READLINE_LINE=${line:point}
    READLINE_POINT=0
    _tafk_tmux_buffer_set "$cut"
}

_tafk_cut_forward_line() {
    local line="$READLINE_LINE" point=$READLINE_POINT cut=${READLINE_LINE:READLINE_POINT}
    [[ -n $cut ]] || return 0
    READLINE_LINE=${line:0:point}
    READLINE_POINT=$point
    _tafk_tmux_buffer_set "$cut"
}

bind -x '"\e[1;2P":_tafk_cut_backward_word' # Ctrl+Shift+Backspace
bind -x '"\e[1;2Q":_tafk_cut_forward_word'  # Ctrl+Shift+Delete
bind -x '"\e[1;2R":_tafk_cut_backward_line' # Alt+Shift+Backspace
bind -x '"\e[1;2S":_tafk_cut_forward_line'  # Alt+Shift+Delete
