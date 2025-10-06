#!/bin/bash
# Core shell functions - Consolidated utilities
# Combines: shared.sh, path.sh, process.sh, help-tmux.sh

# ==============================================================================
# Directory & Navigation Functions
# ==============================================================================

# cd and list - use cdl instead of overriding cd
cdl() {
    builtin cd "$@" && ls
}

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Quick project finder (requires fzf)
proj() {
    local project_dirs=("$HOME/projects" "$HOME/dev" "$HOME/work" "$HOME/code" "$HOME/src")
    local project

    for dir in "${project_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            project=$(find "$dir" -maxdepth 2 -type d -name ".git" | sed 's|/.git||' | sed "s|$dir/||" | fzf --preview "ls -la $dir/{}")
            if [[ -n "$project" ]]; then
                cd "$dir/$project"
                return
            fi
        fi
    done
}

# ==============================================================================
# PATH Management Functions
# ==============================================================================

# Add directory to PATH if it exists and isn't already in PATH
add_to_path() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
    fi
}

# Remove duplicates from PATH
dedupe_path() {
    local new_path=""
    local IFS=':'
    for dir in $PATH; do
        if [[ ":$new_path:" != *":$dir:"* ]]; then
            new_path="${new_path:+$new_path:}$dir"
        fi
    done
    export PATH="$new_path"
}

# Show PATH entries one per line
show_path() {
    echo "$PATH" | tr ':' '\n'
}

# ==============================================================================
# Process Management Functions
# ==============================================================================

# Process search function
psg() {
    if [[ -z "$1" ]]; then
        echo "Usage: psg <process_name>"
        echo "Search for running processes matching the given name"
        return 1
    fi
    ps aux | grep -v grep | grep -i "$1"
}

# Find and kill process (requires fzf)
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if [[ -n $pid ]]; then
        echo "$pid" | xargs kill -"${1:-9}"
    fi
}

# ==============================================================================
# Archive & File Functions
# ==============================================================================

# Extract function for various archive types
extract() {
    if [[ -f $1 ]]; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.xz)        unxz "$1"        ;;
            *.lzma)      unlzma "$1"      ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Quick notes function
note() {
    local note_file="$HOME/.notes"
    if [[ $# -eq 0 ]]; then
        if [[ -f "$note_file" ]]; then
            if command -v bat >/dev/null 2>&1; then
                bat "$note_file"
            else
                cat "$note_file"
            fi
        fi
    else
        echo "$(date): $*" >> "$note_file"
    fi
}

# ==============================================================================
# Help & Documentation Functions
# ==============================================================================

# Display tmux help and cheat sheet
help-tmux() {
    cat << 'EOF'
Tmux Cheat Sheet - Common Commands

PREFIX KEY: Ctrl-a (instead of default Ctrl-b)

SESSIONS:
  tmux                    Create new session
  tmux new -s name        Create new named session
  tmux ls                 List sessions
  tmux attach -t name     Attach to named session
  tmux kill-session -t name   Kill named session

WINDOWS (within tmux):
  Ctrl-a c               Create new window
  Ctrl-a n               Next window
  Ctrl-a p               Previous window
  Ctrl-a w               List windows
  Ctrl-a &               Kill current window
  Ctrl-a ,               Rename current window

PANES:
  Ctrl-a |               Split vertically
  Ctrl-a -               Split horizontally
  Ctrl-a Left/Right/Up/Down   Navigate panes
  Alt-Arrow              Navigate panes (no prefix needed)
  Ctrl-a x               Kill current pane
  Ctrl-a z               Toggle pane zoom

COPY MODE:
  Ctrl-a [               Enter copy mode
  Space                  Start selection (in copy mode)
  Enter                  Copy selection (in copy mode)
  Ctrl-a ]               Paste

OTHER:
  Ctrl-a d               Detach from session
  Ctrl-a r               Reload tmux config
  Ctrl-a ?               Show all key bindings
  Ctrl-a :               Enter command mode

SESSION MANAGEMENT SHORTCUTS:
  tm <name>              Create/attach to named session
  ta <name>              Attach to session
  tl                     List sessions
EOF
}

# Note: SSH key import is handled by lib/core.sh import_windows_ssh_keys() function
# Use: sync-ssh command (alias to lib/core.sh function)
