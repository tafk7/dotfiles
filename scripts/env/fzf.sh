#!/bin/bash

# Enhanced FZF Configuration for Visual Workflow

# ==============================================================================
# FZF Core Settings
# ==============================================================================

# Default options with preview window
export FZF_DEFAULT_OPTS="
    --height 60%
    --layout=reverse
    --border=rounded
    --preview-window=right:60%:wrap
    --bind 'ctrl-/:change-preview-window(down|hidden|)'
    --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
    --bind 'ctrl-e:execute(echo {+} | xargs -o $EDITOR)'
    --bind 'ctrl-v:execute(code {+})'
    --color=bg+:#414559,bg:#303446,spinner:#f2d5cf,hl:#e78284
    --color=fg:#c6d0f5,header:#e78284,info:#ca9ee6,pointer:#f2d5cf
    --color=marker:#f2d5cf,fg+:#c6d0f5,prompt:#ca9ee6,hl+:#e78284"

# ==============================================================================
# File Search Configuration
# ==============================================================================

# Use fd if available for better performance
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
fi

# ==============================================================================
# Preview Configuration
# ==============================================================================

# Ctrl-T: File preview with syntax highlighting
if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'bat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'
        --header 'CTRL-V: Open in VS Code | CTRL-E: Open in Editor | CTRL-P: Toggle Preview'"
elif command -v batcat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'batcat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'
        --header 'CTRL-V: Open in VS Code | CTRL-E: Open in Editor | CTRL-P: Toggle Preview'"
else
    export FZF_CTRL_T_OPTS="
        --preview 'cat {}'
        --bind 'ctrl-p:toggle-preview'"
fi

# Alt-C: Directory preview with tree
if command -v eza >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'eza --tree --color=always --level=2 --icons {} | head -200'
        --bind 'ctrl-p:toggle-preview'
        --header 'Navigate directories | CTRL-P: Toggle Preview'"
elif command -v tree >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'tree -C {} | head -200'
        --bind 'ctrl-p:toggle-preview'"
fi

# ==============================================================================
# History Configuration
# ==============================================================================

# Ctrl-R: Better history search
export FZF_CTRL_R_OPTS="
    --preview 'echo {}'
    --preview-window down:3:hidden:wrap
    --bind 'ctrl-p:toggle-preview'
    --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
    --header 'CTRL-Y: Copy to clipboard | CTRL-P: Toggle Preview'
    --exact"

# ==============================================================================
# Custom FZF Functions
# ==============================================================================

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

# ==============================================================================
# Aliases for Quick Access
# ==============================================================================

alias gb='fzf-git-branch'
alias gl='fzf-git-log'
alias rg='fzf-rg'
alias fp='fzf-project'

# Integration with z/zoxide for fuzzy directory jumping
if command -v zoxide >/dev/null 2>&1; then
    alias zi='zoxide query -i'  # Interactive mode with fzf
fi