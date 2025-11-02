#!/bin/bash

# Essential git aliases for daily use
# Naming convention: g + command abbreviation
# Letters consistently map to commands: s=status/switch/staged, d=diff, c=commit, etc.

# Status and inspection
alias gs='git status'
alias gl='git log --oneline --decorate --graph'

# Staging and changes
alias ga='git add'
alias gaa='git add .'
alias gau='git add -u'
alias gd='git diff'
alias gds='git diff --staged'

# Commits
alias gc='git commit'
alias gcm='git commit -m'

# Branches (modern switch commands, Git 2.23+)
alias gsw='git switch'
alias gswc='git switch -c'
alias gb='git branch'

# Fetch operations
alias gf='git fetch'
alias gfo='git fetch origin'
alias gfu='git fetch upstream'
alias gfa='git fetch --all'

# Push/pull
alias gp='git push'
alias gpl='git pull'

# Stash
alias gst='git stash'
alias gstp='git stash pop'

# Lazygit TUI
alias lg='lazygit'

# Useful functions

# Undo last commit but keep changes
gundo() {
    git reset HEAD~1 --soft
}