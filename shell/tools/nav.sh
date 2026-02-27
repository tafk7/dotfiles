#!/bin/bash
# Navigation and PATH management functions

# cd and list
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

# Markdown viewer — TUI when interactive, rendered output when piped
md() {
    if ! command -v glow >/dev/null 2>&1; then
        cat "$@"
        return
    fi
    if [[ -t 1 ]]; then
        glow "$@"
    else
        glow -p "$@"
    fi
}
