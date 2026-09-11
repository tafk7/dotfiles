#!/bin/bash
# Tmux — aliases and functions

# Session management
alias tm='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

# Tmux resume: outside tmux, attach to the most recently used session (tmux
# prefers an unattached one). Inside tmux, switch to the last session. Preserve
# the standard `tr` utility whenever arguments are supplied.
unalias tr 2>/dev/null
tr() {
    if (( $# > 0 )); then
        command tr "$@"
    elif [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -l
    else
        tmux attach-session
    fi
}

# Pane tinting — apply themed background variant to current pane
pane-tint() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "Not in a tmux session"
        return 1
    fi

    local level="${1:-}"

    if ! "$DOTFILES_DIR/bin/theme-switcher" enabled 2>/dev/null; then
        echo "Theme feature is disabled"
        return 1
    fi

    if [[ -z "$level" ]]; then
        echo "Usage: pane-tint <0|1|2|3>"
        return 0
    fi

    "$DOTFILES_DIR/bin/theme-switcher" tint "$level" "$TMUX_PANE"
}
