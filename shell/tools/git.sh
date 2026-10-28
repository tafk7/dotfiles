#!/bin/bash
# Git — aliases and functions

# Status and inspection
alias gs='git status'
alias gl='git log --oneline --decorate --graph'

# Clone: git clone, or with -p PROFILE as that git profile (bin/git-profile);
# git clone itself has no -p. A shell that defined gcl as an alias would expand
# it inside the definition, so the alias goes first.
unalias gcl 2>/dev/null
gcl() {
    if [[ "${1:-}" == -p ]]; then
        shift
        git profile clone "$@"
    else
        git clone "$@"
    fi
}

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

# Undo last commit but keep changes
gundo() {
    git reset HEAD~1 --soft
}
