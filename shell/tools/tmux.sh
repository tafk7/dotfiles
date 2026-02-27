#!/bin/bash
# Tmux — aliases and functions

# Session management
alias tm='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

# Pane tinting — apply themed background variant to current pane
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

    if [[ "$level" == "reset" || "$level" == "0" ]]; then
        tmux select-pane -P 'default'
        return 0
    fi

    # THEME_TINT_* variables are in the environment from the shell theme
    # loader. Fall back to sourcing colors.sh directly if missing.
    if [[ -z "${THEME_TINT_1:-}" ]]; then
        local theme_name="${DOTFILES_THEME:-gruvbox}"
        local dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
        local colors_file="$dotfiles_dir/themes/$theme_name/colors.sh"

        if [[ ! -f "$colors_file" ]]; then
            echo "Theme colors not found: $colors_file"
            return 1
        fi
        source "$colors_file"
    fi

    local hex
    case "$level" in
        1) hex="$THEME_TINT_1" ;;
        2) hex="$THEME_TINT_2" ;;
        3) hex="$THEME_TINT_3" ;;
        *)
            echo "Unknown level: $level"
            echo "Available: 0, 1, 2, 3"
            return 1
            ;;
    esac

    tmux select-pane -P "bg=$hex"
}
