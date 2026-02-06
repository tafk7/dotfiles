#!/bin/bash
# Core shell functions and utilities

# ==============================================================================
# Directory & Navigation Functions
# ==============================================================================

# cd and list - use cdl instead of overriding cd
cdl() {
    builtin cd "$@" && ls
}

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Quick project finder (requires fzf)
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

# ==============================================================================
# PATH Management Functions
# ==============================================================================

# Add directory to PATH if it exists and isn't already in PATH
add_to_path() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
    fi
}

# Remove duplicates from PATH
dedupe_path() {
    local new_path=""
    local IFS=':'
    for dir in $PATH; do
        if [[ ":$new_path:" != *":$dir:"* ]]; then
            new_path="${new_path:+$new_path:}$dir"
        fi
    done
    export PATH="$new_path"
}

# Show PATH entries one per line
show_path() {
    echo "$PATH" | tr ':' '\n'
}

# ==============================================================================
# Process Management Functions
# ==============================================================================

# Process search function
psg() {
    if [[ -z "$1" ]]; then
        echo "Usage: psg <process_name>"
        echo "Search for running processes matching the given name"
        return 1
    fi
    ps aux | grep -v grep | grep -i "$1"
}

# Find and kill process (requires fzf)
fkill() {
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if [[ -n $pid ]]; then
        echo "$pid" | xargs kill -"${1:-9}"
    fi
}

# ==============================================================================
# Archive & File Functions
# ==============================================================================

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

# ==============================================================================
# WSL Functions
# ==============================================================================

# Import SSH keys from Windows (WSL only) — self-contained for runtime use
import_windows_ssh_keys() {
    if ! command -v wslpath >/dev/null 2>&1; then
        echo "Not running on WSL — nothing to do."
        return 0
    fi

    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
    if [[ -z "$win_user" ]] || [[ "$win_user" == "SYSTEM" ]] || [[ "$win_user" == "Administrator" ]]; then
        win_user="$USER"
    fi

    local windows_ssh_dir="/mnt/c/Users/$win_user/.ssh"

    if [[ ! -d "$windows_ssh_dir" ]]; then
        echo "No Windows SSH directory found at $windows_ssh_dir"
        return 0
    fi

    echo "Importing SSH keys from Windows ($windows_ssh_dir)..."

    local ssh_dir="$HOME/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    for key_file in "$windows_ssh_dir"/*; do
        if [[ -f "$key_file" ]]; then
            local filename=$(basename "$key_file")
            local target="$ssh_dir/$filename"

            cp "$key_file" "$target"

            if [[ "$filename" == *.pub ]]; then
                chmod 644 "$target"
            else
                chmod 600 "$target"
            fi

            echo "  Imported: $filename"
        fi
    done

    echo "SSH key import completed."
}

# ==============================================================================
# FZF Advanced Functions
# Optional enhanced FZF integrations for git, ripgrep, projects, etc.
#
# To enable: Add to ~/.zshrc.local or ~/.bashrc.local:
#   Merged into shell/functions.sh from scripts/functions/fzf-extras.sh

# ==============================================================================
# Git Integration Functions
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

# ==============================================================================
# Search Functions
# ==============================================================================

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

# ==============================================================================
# Project Management
# ==============================================================================

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
# Aliases for Quick Access (prefixed with 'f' to avoid conflicts)
# ==============================================================================

alias fgb='fzf-git-branch'   # FZF git branch switcher
alias fgl='fzf-git-log'      # FZF git log browser
alias frg='fzf-rg'           # FZF ripgrep search (rg is ripgrep itself)
alias fp='fzf-project'       # FZF project finder

# ==============================================================================
# Python & Poetry Management Functions
# ==============================================================================

# Set Python version for current project (works for both Poetry and pip projects)
pyset() {
    if ! command -v pyenv >/dev/null 2>&1; then
        echo "Error: pyenv is not installed"
        return 1
    fi

    # Handle --default flag
    if [[ "$1" == "--default" ]]; then
        if [[ -z "$2" ]]; then
            echo "Usage: pyset --default <python-version>"
            echo "Example: pyset --default 3.11.9"
            echo ""
            echo "Available Python versions:"
            pyenv versions --bare
            return 1
        fi

        local version="$2"

        # Check if version is installed
        if ! pyenv versions --bare | grep -q "^${version}$"; then
            echo "Python ${version} is not installed."
            echo "Install it with: pyenv install ${version}"
            return 1
        fi

        # Set global Python version
        pyenv global "$version"

        # Clean up legacy state file (migration from old wrapper system)
        rm -f "$HOME/.config/dotfiles/default-python-version"

        echo ""
        echo "✓ Default Python version set to ${version}"
        echo "✓ python and python3 commands now available globally"
        echo ""
        echo "This version will be used everywhere unless overridden by:"
        echo "  - A project's .python-version file (pyenv local)"
        echo "  - A .envrc with 'layout pyenv <version>' (direnv)"
        return 0
    fi

    if [[ -z "$1" ]]; then
        echo "Usage: pyset <python-version>"
        echo "       pyset --default <python-version>"
        echo ""
        echo "Examples:"
        echo "  pyset 3.11.9              # Set Python version for current project"
        echo "  pyset --default 3.11.9    # Set global default Python version"
        echo ""
        echo "Available Python versions:"
        pyenv versions --bare
        return 1
    fi

    local version="$1"

    # Check if version is installed
    if ! pyenv versions --bare | grep -q "^${version}$"; then
        echo "Python ${version} is not installed."
        echo "Install it with: pyenv install ${version}"
        return 1
    fi

    # Set local Python version
    echo "Setting Python version to ${version}..."
    pyenv local "$version"

    # Detect project type and configure accordingly
    if [[ -f pyproject.toml ]] && command -v poetry >/dev/null 2>&1; then
        # Poetry project
        echo "Configuring Poetry to use Python ${version}..."
        poetry env use python

        echo ""
        echo "✓ Python version set to ${version}"
        echo "✓ Poetry configured to use this version"
        echo ""
        echo "Next: Run 'poetry install' to create/update the virtual environment"
    else
        # pip project or no package manager
        # Remove old venv if it exists
        if [[ -d .venv ]]; then
            echo "Removing existing .venv..."
            rm -rf .venv
        fi

        # Create new venv (prefer uv for speed)
        echo "Creating virtual environment..."
        if command -v uv >/dev/null 2>&1; then
            uv venv .venv --python "$(pyenv which python)"
        else
            python -m venv .venv
        fi

        echo ""
        echo "✓ Python version set to ${version}"
        echo "✓ Virtual environment created at .venv/"
        echo ""
        echo "Next steps:"
        echo "  1. Activate: vactivate (or: source .venv/bin/activate)"
        if command -v uv >/dev/null 2>&1; then
            if [[ -f requirements.txt ]]; then
                echo "  2. Install: uv pip install -r requirements.txt"
            else
                echo "  2. Install packages: uv pip install <package-name>"
            fi
        else
            if [[ -f requirements.txt ]]; then
                echo "  2. Install: pip install -r requirements.txt"
            else
                echo "  2. Install packages: pip install <package-name>"
            fi
        fi
        echo ""
        echo "Tip: Add 'layout pyenv ${version}' to .envrc for auto-activation with direnv."
    fi
}

# Show current Python and Poetry environment info
pyinfo() {
    echo "=== Python Environment Info ==="
    echo ""

    # pyenv info
    if command -v pyenv >/dev/null 2>&1; then
        echo "pyenv version:"
        pyenv version
        echo ""

        if [[ -f .python-version ]]; then
            echo "Project Python version (from .python-version):"
            cat .python-version
            echo ""
        fi
    else
        echo "pyenv: not installed"
        echo ""
    fi

    # uv info
    if command -v uv >/dev/null 2>&1; then
        echo "uv: $(uv --version 2>/dev/null)"
    else
        echo "uv: not installed"
    fi
    echo ""

    # direnv info
    if command -v direnv >/dev/null 2>&1; then
        echo "direnv: $(direnv --version 2>/dev/null)"
        if [[ -f .envrc ]]; then
            echo "  .envrc found in current directory"
        fi
    else
        echo "direnv: not installed"
    fi
    echo ""

    # System Python
    echo "Active Python:"
    which python || echo "  python: not found (enforcing venv usage ✓)"
    python --version 2>/dev/null || echo "  No python in PATH (use venv)"
    echo ""

    # Poetry info
    if command -v poetry >/dev/null 2>&1; then
        echo "Poetry environment:"
        poetry env info 2>/dev/null || echo "  No Poetry environment (run 'poetry install')"
    else
        echo "poetry: not installed"
    fi

    # Virtual environment status
    echo ""
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        echo "✓ Virtual environment active: $VIRTUAL_ENV"
    else
        echo "✗ No virtual environment active"
        if [[ -d .venv ]]; then
            echo "  (Found .venv/ - activate with: source .venv/bin/activate)"
        fi
    fi
}

# List all pyenv Python versions with helpful info
pylist() {
    if ! command -v pyenv >/dev/null 2>&1; then
        echo "Error: pyenv is not installed"
        return 1
    fi

    echo "=== Installed Python Versions ==="
    pyenv versions
    echo ""
    echo "=== Available Versions (showing latest patches only) ==="
    pyenv install --list | grep -E '^\s*3\.(8|9|10|11|12|13)\.[0-9]+$' | tail -20
    echo ""
    echo "Install a version: pyenv install <version>"
    echo "Example: pyenv install 3.11.9"
}

# Universal venv activation (works for both Poetry and pip projects)
# Manual venv activation (for projects not using direnv)
vactivate() {
    if [[ -d .venv ]]; then
        source .venv/bin/activate
        echo "✓ Virtual environment activated"

        # Show what type of project this is
        if [[ -f pyproject.toml ]]; then
            echo "  (Poetry project)"
        elif [[ -f requirements.txt ]]; then
            echo "  (pip project)"
        fi
    else
        echo "No .venv found in current directory"

        if [[ -f pyproject.toml ]]; then
            echo "This is a Poetry project. Run: poetry install"
        elif [[ -f requirements.txt ]]; then
            echo "This is a pip project. Run: pyset <version>"
        else
            echo "Run 'pyset <version>' to create one"
        fi
        echo ""
        echo "Tip: Use 'layout pyenv <version>' in .envrc for auto-activation."
        return 1
    fi
}
