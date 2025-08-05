#!/bin/bash
# Core utilities for dotfiles - Arete version
set -euo pipefail

# Colors (only what's needed)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# Essential logging
error() { echo -e "${RED}ERROR:${NC} $1" >&2; }
success() { echo -e "${GREEN}✓${NC} $1"; }

# WSL detection
is_wsl() { [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; }

# Windows username (if needed)
get_windows_username() {
    is_wsl && cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true
}

# Process git config template
setup_git_config() {
    local config="$HOME/.gitconfig"
    [[ -f "$config" ]] && mv "$config" "$config.bak"
    
    if [[ -t 0 ]]; then
        read -p "Git name: " name
        read -p "Git email: " email
    else
        name="$USER"
        email="$USER@localhost"
    fi
    
    sed -e "s/{{GIT_NAME}}/$name/g" \
        -e "s/{{GIT_EMAIL}}/$email/g" \
        "$1" > "$config"
}

# Symlink configs
link_configs() {
    local src="$1" dest="$2"
    [[ -e "$dest" && ! -L "$dest" ]] && mv "$dest" "$dest.bak"
    ln -sf "$src" "$dest"
}

# Validate critical files exist
validate_core() {
    local files=(.bashrc .zshrc .gitconfig)
    for f in "${files[@]}"; do
        [[ ! -e "$HOME/$f" ]] && error "Missing: $f" && return 1
    done
    return 0
}