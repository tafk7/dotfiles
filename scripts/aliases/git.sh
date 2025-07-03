#!/bin/bash

# Essential git aliases for daily use

# Status and staging
alias gs='git status -sb'
alias ga='git add'
alias gaa='git add .'
alias gd='git diff'
alias gdc='git diff --cached'

# Commits
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'

# Branches
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'

# Push/pull
alias gp='git push'
alias gpl='git pull'
alias gpu='git push -u origin HEAD'

# Log viewing
alias gl='git log --oneline --decorate --graph'
alias gla='git log --oneline --decorate --graph --all'

# Stash
alias gst='git stash'
alias gstp='git stash pop'

# Useful functions

# Undo last commit but keep changes
gundo() {
    git reset HEAD~1 --soft
}

# Quick commit and push (with input validation)
gquick() {
    if [[ -z "$1" ]]; then
        echo "Error: Commit message required"
        return 1
    fi
    git add .
    git commit -m "${1}"
    git push
}