#!/bin/bash

# Essential git aliases for daily use
# Naming convention: g + command abbreviation
# Letters consistently map to commands: s=status/switch/staged, d=diff, c=commit, etc.

# Status and inspection
alias gs='git status'
alias gl='git log --oneline --decorate --graph'
alias gla='git log --oneline --decorate --graph --all'

# Staging and changes
alias ga='git add'
alias gaa='git add .'
alias gau='git add -u'
alias gd='git diff'
alias gds='git diff --staged'
alias grs='git restore'
alias grss='git restore --staged'

# Commits
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'

# Branches (modern switch commands, Git 2.23+)
alias gsw='git switch'
alias gswc='git switch -c'
alias gb='git branch'

# Fetch operations
alias gf='git fetch'
alias gfo='git fetch origin'
alias gfu='git fetch upstream'
alias gfa='git fetch --all'
alias gfp='git fetch --prune'

# Push/pull
alias gp='git push'
alias gpl='git pull'
alias gpu='git push -u origin HEAD'

# Stash
alias gst='git stash'
alias gstp='git stash pop'
alias gsta='git stash apply'
alias gstl='git stash list'

# Repository
alias gcl='git clone'

# Lazygit TUI
alias lg='lazygit'

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