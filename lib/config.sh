#!/bin/bash
# Declarative configuration — single source of truth for managed files and packages.
# This file defines data only. No functions. No side effects.

# Tool registry (single source of truth for managed tools)
source "$(dirname "${BASH_SOURCE[0]}")/registry.sh"

# Directory constants
CONFIGS_DIR="$DOTFILES_DIR/configs"
ENTRY_DIR="$DOTFILES_DIR/entry"

# Configuration mappings: key → "target:type:owner"
# Keys under shell/ use SHELL_DIR; keys under configs/ use CONFIGS_DIR.
# setup.sh resolves the source path using config_source_path().
#
# owner (3rd field): the tool a config belongs to. Empty owner = base config,
# always symlinked (the bash dev environment + universal files). A named owner
# means the config is symlinked only when that tool is present on the system
# (config_owner_present in setup.sh), so a bare install never litters configs for
# tools that aren't there, and an org-managed/pre-installed tool still gets its
# config. Owner is a registry tool name where one exists; otherwise a plain
# command name (e.g. zsh, which is an apt package, not a managed tool).
declare -A CONFIG_MAP=(
    # Shell RC files (source: entry/)
    [bash.sh]="$HOME/.bashrc:symlink:"
    [zsh.sh]="$HOME/.zshrc:symlink:zsh"
    [zshenv]="$HOME/.zshenv:symlink:zsh"
    [zprofile]="$HOME/.zprofile:symlink:zsh"
    [profile.sh]="$HOME/.profile:symlink:"
    [bash_profile]="$HOME/.bash_profile:symlink:"

    # Config files (source: configs/)
    [tmux.conf]="$HOME/.tmux.conf:symlink:tmux"
    [editorconfig]="$HOME/.editorconfig:symlink:"
    [ripgreprc]="$HOME/.ripgreprc:symlink:ripgrep"
    [init.vim]="$HOME/.config/nvim/init.vim:symlink:neovim"
    [config/bat]="$HOME/.config/bat:symlink:bat"
    [config/fd]="$HOME/.config/fd:symlink:fd"
    [ssh_config]="$HOME/.ssh/config:symlink:"
    # starship.toml: NOT a symlink. theme-switcher generates immutable
    # cached themes/<theme>/starship.toml files; STARSHIP_CONFIG selects one
    # for the current shell's global/session/window context.

    # Special handling
    [gitconfig]="$HOME/.gitconfig:gitconfig:"
)

# Resolve the source path for a CONFIG_MAP key
config_source_path() {
    local key="$1"
    case "$key" in
        bash.sh|zsh.sh|zshenv|zprofile|profile.sh|bash_profile) echo "$ENTRY_DIR/$key" ;;
        *)                                       echo "$CONFIGS_DIR/$key" ;;
    esac
}

# Decide whether a config's owning tool is present, so setup.sh can skip configs
# for tools that aren't installed. Empty owner = base config, always applied.
# A named owner is checked against reality (registry verify command when it's a
# managed tool, else a plain command -v), NOT against the selected tier — so a
# pre-installed or org-managed tool still gets its config, and a bare install
# lays down nothing orphaned.
config_owner_present() {
    local owner="$1"
    [[ -z "$owner" ]] && return 0
    if [[ -n "${TOOL_BINARY[$owner]:-}" ]]; then
        eval "$(tool_verify_command "$owner")"
    else
        command -v "$owner" >/dev/null 2>&1
    fi
}

# APT package groups. All apt installs live at the dev tier or above — the bash
# tier is sudo-free (eget only). bat/fd/ripgrep/direnv moved to eget, so no
# [modern] group and no direnv here.
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh bison libevent-dev libncurses-dev xclip lsof psmisc"
    [terminal]="htop tree"
    [languages]="python3-pip"
    [wsl]="socat wslu sox libsox-fmt-pulse"  # sox + pulse backend: mic capture for Claude Code /voice via WSLg (plain sox pulls ALSA, which has no /dev/snd in WSL)
    [docker]="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    [diagramming]="graphviz"
    [rdp]="xrdp xorgxrdp xfce4 xfce4-goodies"  # RDP server + Xorg backend + XFCE session (xrdp ships no desktop)
)
