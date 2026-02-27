#!/bin/bash
# FZF advanced integrations — git, ripgrep, and project finder
# Aliases are co-located with their functions (tightly coupled one-liners)

# Interactive git branch switcher
fzf-git-branch() {
    local branches branch
    branches=$(git --no-pager branch -a --color=always | grep -v '/HEAD\s' | sort) &&
    branch=$(echo "$branches" | fzf --height 40% --ansi --multi --tac --preview-window right:70% \
        --preview 'git log --oneline --graph --date=short --color=always --pretty="format:%C(auto)%cd %h%d %s" $(sed s/^..// <<< {} | cut -d" " -f1)' | sed 's/^..//' | cut -d' ' -f1) &&
    git checkout "$(echo "$branch" | sed 's#remotes/##')"
}

# Interactive git commit browser
fzf-git-log() {
    git log --graph --color=always \
        --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --multi --bind 'ctrl-s:toggle-sort' \
        --header 'Press CTRL-S to toggle sort' \
        --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | xargs git show --color=always' \
        --bind 'ctrl-m:execute:
            (grep -o "[a-f0-9]\{7,\}" | head -1 |
            xargs -I % sh -c "git show --color=always % | less -R") <<< {}'
}

# File content search with ripgrep
fzf-rg() {
    local RG_PREFIX="rg --column --line-number --no-heading --color=always --smart-case "
    local INITIAL_QUERY="${*:-}"
    : | fzf --ansi --disabled --query "$INITIAL_QUERY" \
        --bind "start:reload:$RG_PREFIX {q}" \
        --bind "change:reload:sleep 0.1; $RG_PREFIX {q} || true" \
        --delimiter : \
        --preview 'bat --color=always {1} --highlight-line {2}' \
        --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
        --bind 'ctrl-v:execute(code -g {1}:{2})'
}

# Project finder
fzf-project() {
    local project_dirs=("$HOME/projects" "$HOME/work" "$HOME/dev")
    local project
    project=$(find "${project_dirs[@]}" -maxdepth 2 -type d 2>/dev/null |
              fzf --preview 'eza --tree --color=always --level=1 {} | head -20' \
                  --header 'Select project directory')
    [[ -n "$project" ]] && cd "$project"
}

# Quick-access aliases
alias fgb='fzf-git-branch'
alias fgl='fzf-git-log'
alias frg='fzf-rg'
alias fp='fzf-project'
