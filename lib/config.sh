#!/bin/bash
# Declarative configuration — single source of truth for managed files and
# packages. Data plus side-effect-free lookups.

source "$(dirname "${BASH_SOURCE[0]}")/registry.sh"

CONFIGS_DIR="$DOTFILES_DIR/configs"
ENTRY_DIR="$DOTFILES_DIR/entry"

# Pins come from versions.lock (lib/versions.sh), the one version authority.
# sbx is held in APT at its pin: it changes weekly, and kits and controllers
# built on it need an exact version. Neovim and tmux carry their release
# assets' SHA-256, so installing needs no GitHub API lookup.
source "$(dirname "${BASH_SOURCE[0]}")/versions.sh"
SBX_VERSION="$(versions_field sbx want any)"
NVIM_VERSION="$(versions_field neovim want x86_64)"; NVIM_VERSION="${NVIM_VERSION#v}"
declare -A NVIM_SHA256=(
    [x86_64]="$(versions_field neovim sha256 x86_64)"
    [arm64]="$(versions_field neovim sha256 aarch64)"
)
TMUX_VERSION="$(versions_field tmux want any)"
TMUX_SHA256="$(versions_field tmux sha256 any)"
EGET_VERSION="$(versions_field eget want x86_64)"; EGET_VERSION="${EGET_VERSION#v}"
NVM_VERSION="$(versions_field nvm want any)"; NVM_VERSION="${NVM_VERSION#v}"

# The docker-container BuildKit builder sbx kit builds use when Docker's image
# store has no OCI exporter (BUILDX_BUILDER=sbx-kits). Optional, untracked
# buildkitd settings such as a site's DNS servers: SBX_KITS_BUILDKITD_CONFIG.
SBX_KITS_BUILDER="sbx-kits"
SBX_KITS_BUILDKITD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/buildkitd-sbx-kits.toml"

# Configuration mappings: key → "target:type:owner". config_source_path()
# resolves the key to entry/ or configs/.
#
# An empty owner means the config is always linked. A named owner (a registry
# tool, else a plain command such as zsh) links it only when that tool is
# present, whoever installed it, so no config is left without its tool.
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
    [init.vim]="${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.vim:symlink:neovim"
    [config/bat]="${XDG_CONFIG_HOME:-$HOME/.config}/bat:symlink:bat"
    [config/fd]="${XDG_CONFIG_HOME:-$HOME/.config}/fd:symlink:fd"
    [ssh_config]="$HOME/.ssh/config:symlink:"
    [starship.toml]="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml:symlink:starship"

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

# Whether a config's owner is actually present (not whether the selected tier
# includes it), so pre-installed and org-managed tools still get their config.
config_owner_present() {
    local owner="$1"
    [[ -z "$owner" ]] && return 0
    if [[ -n "${TOOL_BINARY[$owner]:-}" ]]; then
        tool_is_present "$owner"
    else
        command -v "$owner" >/dev/null 2>&1
    fi
}

# The portable Git configuration setup renders and ~/.gitconfig includes.
portable_gitconfig_path() {
    printf '%s/dotfiles/gitconfig\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

# render_portable_gitconfig SOURCE: the portable Git config for this machine on
# stdout: the conflict style its Git supports, and the editor, merge tool, and
# pager lines only where nvim and delta are installed.
render_portable_gitconfig() {
    local git_version conflict_style=diff3 has_nvim=0 has_delta=0
    command -v nvim >/dev/null 2>&1 && has_nvim=1
    command -v delta >/dev/null 2>&1 && has_delta=1
    git_version="$(git --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)"
    if [[ -n "$git_version" ]] && version_gte "$git_version" "2.35"; then
        conflict_style=zdiff3
    fi
    sed -e "s|{{CONFLICT_STYLE}}|$conflict_style|g" "$1" |
        awk -v nvim="$has_nvim" -v delta="$has_delta" '
            !nvim && /^[[:space:]]*(editor = nvim|tool = nvimdiff)$/ { next }
            !delta && /^[[:space:]]*(pager = delta|diffFilter = delta --color-only)$/ { next }
            { print }
        '
}

# Whether a deployed target sits under the roots setup may change: inside
# $HOME, or inside a custom XDG_CONFIG_HOME, never either root itself.
config_target_approved() {
    local target="$1" home parent canon config
    [[ "$target" == /* ]] || return 1
    home="$(cd "$HOME" 2>/dev/null && pwd -P)" || return 1
    parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
    canon="$parent/$(basename "$target")"
    config="$(realpath -m -- "${XDG_CONFIG_HOME:-$HOME/.config}")"
    [[ "$canon" == "$home"/* ]] && return 0
    [[ "$config" != / && "$canon" == "$config"/* ]]
}

# APT package groups. Tier-owned APT starts at dev; the bash tier is sudo-free.
declare -A PACKAGES=(
    [core]="git build-essential locales"
    [development]="zsh bison libevent-dev libncurses-dev xclip lsof psmisc"
    [terminal]="htop tree"
    [languages]="python3-pip"
    [wsl]="socat wslu sox libsox-fmt-pulse"  # sox + pulse backend: mic capture for Claude Code /voice via WSLg (plain sox pulls ALSA, which has no /dev/snd in WSL)
    [docker]="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    [diagramming]="graphviz"
    [rdp]="xrdp xorgxrdp xfce4 xfce4-goodies"  # RDP server + Xorg backend + XFCE session (xrdp ships no desktop)
)
