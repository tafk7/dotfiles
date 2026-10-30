#!/bin/bash
# Git — aliases and functions

# Status and inspection
alias gs='git status'                            # Show working tree status and staged changes
alias gl='git log --oneline --decorate --graph'  # Show commit history as decorated graph

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
alias ga='git add'             # Stage specific files for commit
alias gaa='git add .'          # Stage all changes in working directory
alias gau='git add -u'         # Stage all tracked files that have changes
alias gd='git diff'            # Show unstaged changes in working directory
alias gds='git diff --staged'  # Show staged changes ready to commit

# Commits
alias gc='git commit'      # Create commit with editor for message
alias gcm='git commit -m'  # Create commit with inline message

# Branches (modern switch commands, Git 2.23+)
alias gsw='git switch'      # Switch to existing branch
alias gswc='git switch -c'  # Create and switch to new branch
alias gb='git branch'       # List all local branches

# Fetch operations
alias gf='git fetch'            # Download objects and refs from remote
alias gfo='git fetch origin'    # Download latest changes from origin remote
alias gfu='git fetch upstream'  # Download latest changes from upstream remote
alias gfa='git fetch --all'     # Download changes from all configured remotes

# Push/pull
alias gp='git push'   # Upload local commits to remote
alias gpl='git pull'  # Download and merge remote changes

# Stash
alias gst='git stash'       # Save working changes to temporary area
alias gstp='git stash pop'  # Apply and remove most recent stash

# Lazygit TUI
alias lg='lazygit'  # Launch interactive terminal UI for git

# Undo the last commit but keep its changes staged
gundo() {
    git reset HEAD~1 --soft
}
