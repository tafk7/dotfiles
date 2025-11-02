#!/bin/bash

# VS Code aliases for quick access

# Quick open VS Code
alias c='code .'

# Open specific files/folders in VS Code
alias cdot='code $DOTFILES_DIR'

# Quick project navigation + open
cproj() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for cproj" >&2
        return 1
    fi

    local dir
    local search_dirs="${PROJECTS_DIR:-$HOME/projects} $HOME/.config"
    dir=$(find $search_dirs -maxdepth 2 -type d 2>/dev/null | fzf --preview 'ls -la {}')
    [[ -n "$dir" ]] && code "$dir"
}

# Open file in VS Code from fzf search
cf() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for cf" >&2
        return 1
    fi

    local file
    # Use bat/batcat for preview if available, fallback to cat
    if command -v bat >/dev/null 2>&1; then
        file=$(fzf --preview 'bat --style=numbers --color=always {}')
    elif command -v batcat >/dev/null 2>&1; then
        file=$(fzf --preview 'batcat --style=numbers --color=always {}')
    else
        file=$(fzf --preview 'cat {}')
    fi
    [[ -n "$file" ]] && code "$file"
}

# Quick diff between files in VS Code
cdiff() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: cdiff <file1> <file2>"
        return 1
    fi
    code --diff "$1" "$2"
}

# Note: EDITOR is set in env/common.sh (nvim by default)
# To use VS Code as your default editor, add to ~/.zshrc.local:
#   export EDITOR='code --wait'
#   export VISUAL='code --wait'
#   export GIT_EDITOR='code --wait'