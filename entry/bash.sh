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

# Non-interactive: just set PATH baseline and stop.
#
# This branch IS the agent shell. Coding harnesses run commands as `bash -lc`
# (Codex) or snapshot a non-interactive login shell and source that snapshot on
# every tool call (Claude Code, and Codex's unified_exec shell_snapshot). Either
# way they land here, via entry/bash_profile -> ~/.bashrc.
if [[ $- != *i* ]]; then
    [[ -f "$HOME/.profile" ]] && source "$HOME/.profile"

    # Drop functions inherited from /etc/profile.d. They are dead weight in a
    # non-interactive shell and actively expensive downstream: Claude Code
    # re-encodes every captured function into its snapshot as
    #   eval "$(echo '<base64>' | base64 -d)"
    # which is a subshell plus a `base64` exec PER FUNCTION, paid on every
    # single tool call. Six trivial gawk AWKPATH helpers from
    # /etc/profile.d/gawk.sh accounted for 30ms of a 40ms call here (26
    # clone+execve syscalls vs 2 without them).
    #
    # Generic rather than a hardcoded name list so the next profile.d package
    # that ships functions is neutralised automatically. Interactive shells
    # never reach this line — the whole branch is non-interactive only — so
    # bash-completion and our own tool functions are untouched.
    #
    # `declare -F` emits "declare -f NAME" per line; strip the prefix with a
    # parameter expansion rather than piping to awk. This runs on every
    # `bash -lc`, so its own cost matters: the awk pipeline measured 9.1ms per
    # call (two forks + an exec), which would have made Codex's per-call path
    # slower than it started. The substitution form is one subshell, ~1.5ms.
    #
    # $_dotfiles_fns is unquoted on purpose — word splitting is what turns the
    # newline-separated list into arguments. An empty expansion is a harmless
    # no-op that still exits 0.
    _dotfiles_fns=$(declare -F)
    # shellcheck disable=SC2086
    unset -f ${_dotfiles_fns//declare -f /} 2>/dev/null || true
    unset _dotfiles_fns

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
