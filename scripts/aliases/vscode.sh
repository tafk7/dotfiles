#!/bin/bash

# VS Code aliases for quick access

# Quick open VS Code
alias c='code .'
alias cc='code .'
alias vsc='code .'

# Open specific files/folders in VS Code
alias cz='code ~/.zshrc'
alias cb='code ~/.bashrc'
alias cdot='code $DOTFILES_DIR'
alias ctodo='code $DOTFILES_DIR/_artifacts/issues/'

# Open VS Code with specific profiles
alias cw='code . --profile "Work"'
alias cp='code . --profile "Personal"'

# Git + VS Code workflow
alias gdc='git diff --cached | code -'  # View staged changes in VS Code
alias gdiff='git diff | code -'         # View changes in VS Code

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

# Search content and open in VS Code
cgrep() {
    if ! command -v rg >/dev/null 2>&1; then
        echo "Error: ripgrep (rg) is required for cgrep" >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "Error: fzf is required for cgrep" >&2
        return 1
    fi

    local file line
    local bat_cmd="cat"
    command -v bat >/dev/null 2>&1 && bat_cmd="bat --style=numbers --color=always"
    command -v batcat >/dev/null 2>&1 && bat_cmd="batcat --style=numbers --color=always"

    read -r file line <<<$(rg --line-number "${1:-.}" | fzf --delimiter ':' --preview "$bat_cmd --highlight-line {2} {1}" | awk -F':' '{print $1, $2}')
    [[ -n "$file" ]] && code --goto "$file:$line"
}

# Quick diff between files in VS Code
cdiff() {
    if [[ $# -ne 2 ]]; then
        echo "Usage: cdiff <file1> <file2>"
        return 1
    fi
    code --diff "$1" "$2"
}

# Open VS Code settings
alias csettings='code ~/.config/Code/User/settings.json'
alias ckeys='code ~/.config/Code/User/keybindings.json'

# VS Code workspace management
alias cws='code *.code-workspace 2>/dev/null || echo "No workspace file found"'

# Note: EDITOR is set in env/common.sh (nvim by default)
# To use VS Code as your default editor, add to ~/.zshrc.local:
#   export EDITOR='code --wait'
#   export VISUAL='code --wait'
#   export GIT_EDITOR='code --wait'