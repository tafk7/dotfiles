#!/bin/bash
# Simple state tracking for dotfiles installation

STATE_FILE="$HOME/.dotfiles_state"

# Log an action to the state file
log_action() {
    local action="$1"
    echo "$(date +%Y%m%d-%H%M%S) $action" >> "$STATE_FILE"
}

# Check if an action has been performed
check_installed() {
    local component="$1"
    [[ -f "$STATE_FILE" ]] && grep -q "$component" "$STATE_FILE" 2>/dev/null
}

# Mark a component as installed
mark_installed() {
    local component="$1"
    if ! check_installed "$component"; then
        log_action "INSTALLED: $component"
    fi
}

# Clear state file (for fresh installs)
clear_state() {
    > "$STATE_FILE"
    log_action "STATE_CLEARED"
}

# Show installation history
show_state() {
    if [[ -f "$STATE_FILE" ]]; then
        echo "Installation history:"
        cat "$STATE_FILE"
    else
        echo "No installation history found"
    fi
}