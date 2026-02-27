#!/bin/bash
# Declarative configuration — single source of truth for managed files and packages.
# This file defines data only. No functions. No side effects.

# Directory constants
CONFIGS_DIR="$DOTFILES_DIR/configs"
SHELL_DIR="$DOTFILES_DIR/shell"

# Configuration mappings: key → "target:type"
# Keys under shell/ use SHELL_DIR; keys under configs/ use CONFIGS_DIR.
# setup.sh resolves the source path using config_source_path().
declare -A CONFIG_MAP=(
    # Shell RC files (source: shell/)
    [bash.sh]="$HOME/.bashrc:symlink"
    [zsh.sh]="$HOME/.zshrc:symlink"
    [profile.sh]="$HOME/.profile:symlink"

    # Config files (source: configs/)
    [tmux.conf]="$HOME/.tmux.conf:symlink"
    [editorconfig]="$HOME/.editorconfig:symlink"
    [ripgreprc]="$HOME/.ripgreprc:symlink"
    [init.vim]="$HOME/.config/nvim/init.vim:symlink"
    [config/bat]="$HOME/.config/bat:symlink"
    [config/fd]="$HOME/.config/fd:symlink"
    [ssh_config]="$HOME/.ssh/config:symlink"
    [starship.toml]="$HOME/.config/starship.toml:symlink"

    # Special handling
    [gitconfig]="$HOME/.gitconfig:template"
)

# Resolve the source path for a CONFIG_MAP key
config_source_path() {
    local key="$1"
    case "$key" in
        bash.sh|zsh.sh|profile.sh) echo "$SHELL_DIR/$key" ;;
        *)                          echo "$CONFIGS_DIR/$key" ;;
    esac
}

# APT package groups
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh direnv bison libevent-dev libncurses-dev xclip"
    [modern]="bat fd-find ripgrep"
    [terminal]="htop tree"
    [languages]="python3-pip"
    [wsl]="socat wslu"
    [docker]="docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    [diagramming]="default-jre graphviz"
)
