#!/bin/bash
# Shared functions for both bash and zsh
# Eliminates redundancy between shell configurations

# cd and list - use cdl instead of overriding cd
cdl() {
    builtin cd "$@" && ls
}

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract function for various archive types
extract() {
    if [[ -f $1 ]]; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.xz)        unxz "$1"        ;;
            *.lzma)      unlzma "$1"      ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Quick notes function
note() {
    local note_file="$HOME/.notes"
    if [[ $# -eq 0 ]]; then
        if [[ -f "$note_file" ]]; then
            if command -v bat >/dev/null 2>&1; then
                bat "$note_file"
            else
                cat "$note_file"
            fi
        fi
    else
        echo "$(date): $*" >> "$note_file"
    fi
}

# Quick project finder
proj() {
    local project_dirs=("$HOME/projects" "$HOME/dev" "$HOME/work" "$HOME/code" "$HOME/src")
    local project
    
    for dir in "${project_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            project=$(find "$dir" -maxdepth 2 -type d -name ".git" | sed 's|/.git||' | sed "s|$dir/||" | fzf --preview "ls -la $dir/{}")
            if [[ -n "$project" ]]; then
                cd "$dir/$project"
                return
            fi
        fi
    done
}

# Find and kill process
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if [[ -n $pid ]]; then
        echo "$pid" | xargs kill -"${1:-9}"
    fi
}

# SSH key import is handled by lib/core.sh import_windows_ssh_keys() function
# Use: sync-ssh command (alias to lib/core.sh function)