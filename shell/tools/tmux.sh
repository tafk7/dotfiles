#!/bin/bash
# Tmux — aliases and functions

# Session management
alias tm='tmux new -s'           # Create new named tmux session
alias ta='tmux attach -t'        # Attach to existing tmux session
alias tl='tmux list-sessions'    # List all tmux sessions
alias tk='tmux kill-session -t'  # Kill specific tmux session

# Tmux resume: outside tmux, attach to the most recently used session (tmux
# prefers an unattached one). Inside tmux, switch to the last session. Preserve
# the standard `tr` utility whenever arguments are supplied.
unalias tr 2>/dev/null
tr() {  # Resume the most recently used tmux session (no args; inside tmux, the last session)
    if (( $# > 0 )); then
        command tr "$@"
    elif [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -l
    else
        tmux attach-session
    fi
}

# Tint this tmux pane's background: a subtler shade of the window's theme
pane-tint() {
    if [[ -z "${TMUX:-}" ]]; then
        echo "Not in a tmux session"
        return 1
    fi

    local level="${1:-}"

    if [[ -z "$level" ]]; then
        echo "Usage: pane-tint <0|1|2|3>"
        return 0
    fi

    "$DOTFILES_DIR/bin/theme-switcher" tint "$level" "$TMUX_PANE"
}
