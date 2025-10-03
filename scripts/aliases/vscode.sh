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
    local dir
    dir=$(find ~/projects ~/work -maxdepth 2 -type d 2>/dev/null | fzf --preview 'ls -la {}')
    [[ -n "$dir" ]] && code "$dir"
}

# Open file in VS Code from fzf search
cf() {
    local file
    file=$(fzf --preview 'bat --style=numbers --color=always {}')
    [[ -n "$file" ]] && code "$file"
}

# Search content and open in VS Code
cgrep() {
    local file line
    read -r file line <<<$(rg --line-number "${1:-.}" | fzf --delimiter ':' --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' | awk -F':' '{print $1, $2}')
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

# Integration with git for commit messages
if command -v code >/dev/null 2>&1; then
    export GIT_EDITOR='code --wait'
    export EDITOR='code --wait'
    export VISUAL='code --wait'
fi