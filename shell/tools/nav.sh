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

# Iterate over existing project search roots from $PROJECTS_DIRS (colon-sep).
# Echoes each existing directory on its own line. Used by proj/fzf-project/cproj.
_dotfiles_iter_project_dirs() {
    local IFS=':'
    local dir
    for dir in ${PROJECTS_DIRS:-$HOME/projects:$HOME/work:$HOME/dev:$HOME/code:$HOME/src}; do
        [[ -d "$dir" ]] && printf '%s\n' "$dir"
    done
}

# Quick project finder (requires fzf) — pick a git repo across PROJECTS_DIRS
proj() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for proj" >&2
        return 1
    fi
    local dirs
    mapfile -t dirs < <(_dotfiles_iter_project_dirs)
    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "proj: no project directories found in PROJECTS_DIRS" >&2
        return 1
    fi
    local repo
    repo=$(find "${dirs[@]}" -maxdepth 3 -type d -name .git -prune 2>/dev/null \
        | sed 's|/\.git$||' \
        | fzf --preview 'eza --tree --color=always --level=1 {} 2>/dev/null || ls -la {}')
    [[ -n "$repo" ]] && cd "$repo"
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
