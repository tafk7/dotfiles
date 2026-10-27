#!/bin/bash

# Draft shell commands with AI at the prompt. Type a request and press Alt+I:
# bin/ai-command turns it into a command, which replaces the request in the
# editable buffer. Nothing generated is run or evaluated here. Alt+I on that
# command asks for a correction and continues the same conversation;
# Alt+Shift+I starts a new one, as do a fresh prompt and a new directory.

# Per-shell state in plain shell variables, so each shell and pane has its own.
# Kept across `reload --soft`.
#   _AI_COMMAND_SESSION_ID   the conversation a correction resumes, if any
#   _AI_COMMAND_ACTIVE       1 while the buffer holds a command drafted here
#   _AI_COMMAND_CWD          the directory the conversation is about
#   _AI_COMMAND_LAST_RESULT  the command drafted last, to notice user edits
_AI_COMMAND_SESSION_ID=${_AI_COMMAND_SESSION_ID:-}
_AI_COMMAND_ACTIVE=${_AI_COMMAND_ACTIVE:-0}
_AI_COMMAND_CWD=${_AI_COMMAND_CWD:-}
_AI_COMMAND_LAST_RESULT=${_AI_COMMAND_LAST_RESULT:-}

# Alt+Shift+I, and every new prompt: the drafted command ran or was abandoned.
# Keeps $? for the prompt hooks that run after it.
_ai_command_reset() {
    local rc=$?
    _AI_COMMAND_SESSION_ID=
    _AI_COMMAND_ACTIVE=0
    _AI_COMMAND_CWD=
    _AI_COMMAND_LAST_RESULT=
    return "$rc"
}

# What Alt+I does with the buffer LINE, in _ai_command_mode:
#   new      LINE is a request: start a conversation
#   refine   LINE is the drafted command, maybe edited: ask for a correction
#            and continue the conversation
#   restart  as refine, but in a new conversation, because the directory
#            changed or the last turn failed
# Fails on an empty LINE, with the message in _ai_command_out.
_ai_command_plan() {
    if [[ -z "${1//[[:space:]]/}" ]]; then
        _ai_command_out="ai-command: type a request first"
        return 1
    fi
    if (( ! _AI_COMMAND_ACTIVE )); then
        _ai_command_mode=new
    elif [[ -n "$_AI_COMMAND_SESSION_ID" && "$_AI_COMMAND_CWD" == "$PWD" ]]; then
        _ai_command_mode=refine
    else
        _ai_command_mode=restart
    fi
}

# Send LINE, and with it the correction FEEDBACK unless the mode is new. On
# success the command is in _ai_command_out. On failure _ai_command_out has
# the error and the conversation is dropped: a failed turn is never resumed.
# Request and command line go on stdin, out of the process list. The widgets'
# INT trap sets _ai_command_interrupted: Ctrl+C during Python's startup ends
# the backend with a traceback rather than its own exit status.
_ai_command_send() {
    local line="$1" feedback="${2:-}" backend="$DOTFILES_DIR/bin/ai-command" rc
    local -a args=(--stdin --cwd "$PWD")
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        args+=(--shell "zsh $ZSH_VERSION")
    else
        args+=(--shell "bash ${BASH_VERSION%%[^0-9.]*}")
    fi
    if [[ "$_ai_command_mode" == refine ]]; then
        args+=(--resume)
        [[ "$line" == "$_AI_COMMAND_LAST_RESULT" ]] || args+=(--edited)
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        read -r _AI_COMMAND_SESSION_ID < /proc/sys/kernel/random/uuid
    else
        _AI_COMMAND_SESSION_ID=$(uuidgen 2>/dev/null)
    fi
    args+=(--session "$_AI_COMMAND_SESSION_ID")
    if [[ ! -x "$backend" ]]; then
        _ai_command_out="ai-command: $backend is missing"
        rc=127
    elif [[ "$_ai_command_mode" == new ]]; then
        _ai_command_out=$(printf '%s' "$line" | "$backend" "${args[@]}" 2>&1)
        rc=$?
    else
        _ai_command_out=$(printf '%s\0%s' "$feedback" "$line" | "$backend" "${args[@]}" 2>&1)
        rc=$?
    fi
    if (( rc == 0 )); then
        _AI_COMMAND_ACTIVE=1
        _AI_COMMAND_CWD=$PWD
        _AI_COMMAND_LAST_RESULT=$_ai_command_out
        return 0
    fi
    _AI_COMMAND_SESSION_ID=
    if (( rc == 130 || ${_ai_command_interrupted:-0} )); then
        _ai_command_out="ai-command: cancelled"
    else
        _ai_command_out=${_ai_command_out##*$'\n'}
        [[ "$_ai_command_out" == ai-command:* ]] || \
            _ai_command_out="ai-command: ${_ai_command_out:-failed with exit status $rc}"
    fi
    return 1
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
    # ZLE widget. The status, the refine> prompt, and messages use ZLE's own
    # area under the buffer, so nothing is written over the prompt.
    _ai_command_widget() {
        # Also makes the INT trap below local to the widget.
        emulate -L zsh
        local line="$BUFFER" feedback="" REPLY _ai_command_interrupted=0
        if ! _ai_command_plan "$line"; then
            zle -M "$_ai_command_out"
            return 1
        fi
        if [[ "$_ai_command_mode" != new ]]; then
            # Ctrl+C, Ctrl+G, and an empty answer leave everything as it was.
            zle read-from-minibuffer 'refine> ' || return 0
            [[ -n "${REPLY//[[:space:]]/}" ]] || return 0
            feedback=$REPLY
        fi
        # Ctrl+C ends the request; untrapped, it would end the widget and
        # discard the line.
        trap '_ai_command_interrupted=1' INT
        zle -R "ai-command: asking ${AI_COMMAND_BACKEND:-claude}... (Ctrl+C cancels)"
        if ! _ai_command_send "$line" "$feedback"; then
            zle -M "$_ai_command_out"
            return 1
        fi
        BUFFER=$_ai_command_out
        CURSOR=${#BUFFER}
    }

    _ai_command_reset_widget() {
        _ai_command_reset
        zle -M "ai-command: the next Alt+I starts a new conversation"
    }

    if [[ -o interactive ]]; then
        autoload -Uz add-zsh-hook read-from-minibuffer
        zle -N read-from-minibuffer
        zle -N ai-command _ai_command_widget
        zle -N ai-command-reset _ai_command_reset_widget
        # entry/zsh.sh selects the emacs keymap after this file runs, and
        # until then "main" may be viins: bind in the emacs keymap by name.
        bindkey -M emacs '^[i' ai-command
        bindkey -M emacs '^[I' ai-command-reset
        add-zsh-hook precmd _ai_command_reset
    fi
else
    # Terminal output for the Bash widget; silent where there is no terminal.
    # shellcheck disable=SC2059  # the caller's format
    _ai_command_tty() { { printf "$@" >/dev/tty; } 2>/dev/null; }

    # Bash Readline widget (bind -x). Readline has cleared the prompt's last
    # line and the buffer, and redraws them when this returns: the status and
    # messages are written in that space.
    _ai_command_widget() {
        local saved_trap _ai_command_interrupted=0
        # Ctrl+C ends the request; untrapped, it would end the widget and
        # discard the line.
        saved_trap=$(trap -p INT)
        trap '_ai_command_interrupted=1' INT
        _ai_command_bash_turn
        eval "${saved_trap:-trap - INT}"
    }

    _ai_command_bash_turn() {
        local line="$READLINE_LINE" feedback="" message
        if ! _ai_command_plan "$line"; then
            _ai_command_tty '%s\n' "$_ai_command_out"
            return
        fi
        if [[ "$_ai_command_mode" != new ]]; then
            _ai_command_ask "$line" || return
            feedback=$_ai_command_feedback
        fi
        message="ai-command: asking ${AI_COMMAND_BACKEND:-claude}... (Ctrl+C cancels)"
        _ai_command_tty '\r\e[K%s' "${message:0:${COLUMNS:-80}-1}"
        if _ai_command_send "$line" "$feedback"; then
            _ai_command_tty '\r\e[K'
            READLINE_LINE=$_ai_command_out
            READLINE_POINT=${#READLINE_LINE}
        else
            _ai_command_tty '\r\e[K%s\n' "$_ai_command_out"
        fi
    }

    # Show the command dimmed with a refine> prompt under it, then erase both.
    # The prompt is a child Bash's `read -e`: Readline is not re-entrant, and
    # a nested `read -e` here would accept, and so run, the outer line too.
    # Fails when the answer is empty or cancelled (Ctrl+C).
    _ai_command_ask() {
        local rc rows
        _ai_command_tty '\r\e[K\e[2m%s\e[0m\n' "$1"
        _ai_command_feedback=$(BASH_ENV='' "$BASH" --norc --noprofile -c \
            'IFS= read -e -r -p "refine> " reply && printf %s "$reply"' </dev/tty 2>/dev/tty)
        rc=$?
        _ai_command_rows "$1"
        rows=$_ai_command_nrows
        _ai_command_rows "refine> $_ai_command_feedback"
        _ai_command_tty '\e[%dA\r\e[J' $(( rows + _ai_command_nrows ))
        (( rc == 0 )) && [[ -n "${_ai_command_feedback//[[:space:]]/}" ]]
    }

    # Terminal rows TEXT takes from column 0, in _ai_command_nrows. Tabs and
    # wide characters count one column, so this can undercount but never
    # erases more than was written.
    _ai_command_rows() {
        local text="$1" line cols=${COLUMNS:-80}
        _ai_command_nrows=0
        while :; do
            line=${text%%$'\n'*}
            (( _ai_command_nrows += ${#line} ? (${#line} + cols - 1) / cols : 1 ))
            [[ "$text" == *$'\n'* ]] || break
            text=${text#*$'\n'}
        done
    }

    _ai_command_reset_widget() {
        _ai_command_reset
        _ai_command_tty '%s\n' "ai-command: the next Alt+I starts a new conversation"
    }

    if [[ $- == *i* ]]; then
        bind -m emacs -x '"\ei": _ai_command_widget'
        bind -m emacs -x '"\eI": _ai_command_reset_widget'
        # Starship moves an existing PROMPT_COMMAND into its own variable.
        [[ "${PROMPT_COMMAND:-} ${STARSHIP_PROMPT_COMMAND:-}" == *_ai_command_reset* ]] || \
            PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_ai_command_reset"
    fi
fi
