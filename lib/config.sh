#!/bin/bash
# Declarative configuration — single source of truth for managed files and
# packages. Data plus side-effect-free lookups.

source "$(dirname "${BASH_SOURCE[0]}")/registry.sh"

CONFIGS_DIR="$DOTFILES_DIR/configs"
ENTRY_DIR="$DOTFILES_DIR/entry"

# Docker Sandboxes, pinned like every other tool and held in APT: sbx changes
# weekly, and kits and controllers built on it (Cardinal requires an exact
# version) break on an unplanned upgrade. Bump deliberately.
SBX_VERSION="0.46.0"
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
