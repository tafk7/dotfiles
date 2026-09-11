#!/bin/bash
# Tool registry — single source of truth for all managed tools.
# Sourced by setup.sh (via config.sh), bin/verify, bin/remove.
# Data only. No side effects.

# Prevent double-sourcing
[[ -n "${_DOTFILES_REGISTRY_LOADED:-}" ]] && return 0
_DOTFILES_REGISTRY_LOADED=1

# TOOL_BINARY: tool name → binary command name in PATH
declare -A TOOL_BINARY=(
    [starship]=starship
    [eza]=eza
    [fzf]=fzf
    [zoxide]=zoxide
    [delta]=delta
    [btop]=btop
    [gdu]=gdu
    [glow]=glow
    [lazygit]=lazygit
    [gh]=gh
    [uv]=uv
    [bat]=bat
    [fd]=fd
    [ripgrep]=rg
    [direnv]=direnv
    [eget]=eget
    [sd]=sd
    [shellcheck]=shellcheck
    [neovim]=nvim
    [tmux]=tmux
    [nvm]=nvm
    [rust]=rustc
    [claude]=claude
    [codex]=codex
    [opencode]=opencode
    [pi]=pi
    [wsl2-ssh-agent]=wsl2-ssh-agent
    [xrdp]=xrdp
    [zsh]=zsh
    [docker]=docker
    [azure-cli]=az
)

# TOOL_METHOD: tool name → install method (eget|apt|installer|external)
declare -A TOOL_METHOD=(
    [starship]=eget
    [eza]=eget
    [fzf]=eget
    [zoxide]=eget
    [delta]=eget
    [btop]=eget
    [gdu]=eget
    [glow]=eget
    [lazygit]=eget
    [gh]=eget
    [uv]=eget
    [bat]=eget
    [fd]=eget
    [ripgrep]=eget
    [direnv]=eget
    [eget]=installer
    [sd]=eget
    [shellcheck]=eget
    [neovim]=installer
    [tmux]=installer
    [nvm]=installer
    [rust]=installer
    [claude]=installer
    [codex]=installer
    [opencode]=installer
    [pi]=installer
    [wsl2-ssh-agent]=eget
    [xrdp]=apt
    [zsh]=apt
    [docker]=apt
    [azure-cli]=apt
)

# TOOL_EGET_REPO: tool name → eget.toml repo slug ("owner/repo")
# Empty = the repo basename is the tool name (starship/starship → starship)
declare -A TOOL_EGET_REPO=(
    [gh]=cli/cli
)

# TOOL_TIER: tool name → tier (bash|dev|work|ai|rdp)
# The cumulative chain is bash→dev→work. The "bash" tier is the non-sudo base:
# every tool in it installs to ~/.local/bin via eget (no root). The sudo boundary
# starts at dev (apt packages: zsh, build tools, clipboard). "ai" and "rdp" are
# orthogonal to the chain: those tools install only under their own flag, never as
# a side effect of a tier. --full implies ai but NOT rdp (a tier must never
# silently open a listener).
declare -A TOOL_TIER=(
    [starship]=bash   [eza]=bash      [fzf]=bash       [zoxide]=bash
    [delta]=bash      [btop]=bash     [glow]=bash       [lazygit]=bash
    [gh]=bash         [uv]=bash       [bat]=bash       [fd]=bash
    [ripgrep]=bash
    [direnv]=bash     [eget]=bash     [sd]=bash        [gdu]=bash
    [neovim]=dev      [tmux]=dev      [shellcheck]=dev
    [wsl2-ssh-agent]=bash
    [claude]=ai       [codex]=ai       [opencode]=ai    [pi]=ai
    [xrdp]=rdp
    [nvm]=work        [rust]=work
    [zsh]=dev         [docker]=work       [azure-cli]=work
)

# Supported platform and architecture inventory. "ubuntu" includes native
# Ubuntu and WSL; wsl is restricted to WSL2. Architecture values are explicit
# so selection-only CI can validate ARM support without pretending to execute
# ARM binaries on an x86 runner.
declare -A TOOL_PLATFORM=()
declare -A TOOL_ARCHES=()
declare -A TOOL_OWNERSHIP_ROOTS=()
declare -A TOOL_UPDATE_CONTRACT=()
declare -A TOOL_UPDATE_SOURCE=(
    [neovim]="neovim/neovim"
    [tmux]="tmux/tmux"
    [nvm]="nvm-sh/nvm"
)
declare -A TOOL_RELATIVE_BINARY=(
    [neovim]="bin/nvim"
)
declare -A TOOL_APT_PACKAGE=(
    [zsh]="zsh"
    [docker]="docker-ce"
    [azure-cli]="azure-cli"
    [xrdp]="xrdp"
)

for _registry_name in "${!TOOL_BINARY[@]}"; do
    TOOL_PLATFORM["$_registry_name"]="ubuntu"
    TOOL_ARCHES["$_registry_name"]="x86_64,aarch64"
done
unset _registry_name
TOOL_PLATFORM[wsl2-ssh-agent]="wsl"

for _registry_name in starship eza fzf zoxide delta btop gdu glow lazygit gh uv bat fd ripgrep direnv sd shellcheck wsl2-ssh-agent; do
    TOOL_OWNERSHIP_ROOTS["$_registry_name"]="$HOME/.local/bin"
    TOOL_UPDATE_CONTRACT["$_registry_name"]="staged-release"
done
unset _registry_name
TOOL_OWNERSHIP_ROOTS[eget]="$HOME/.local/bin"
TOOL_OWNERSHIP_ROOTS[neovim]="$HOME/.local/bin|$HOME/.local/nvim|$HOME/.local/.dotfiles-neovim-rollback"
TOOL_OWNERSHIP_ROOTS[tmux]="$HOME/.local/bin"
TOOL_OWNERSHIP_ROOTS[nvm]="$HOME/.nvm"
TOOL_OWNERSHIP_ROOTS[rust]="$HOME/.cargo|$HOME/.rustup"
TOOL_OWNERSHIP_ROOTS[claude]="$HOME/.local/bin|$HOME/.local/share/claude"
TOOL_OWNERSHIP_ROOTS[codex]="$HOME/.local/bin|$HOME/.codex/packages/standalone"
TOOL_OWNERSHIP_ROOTS[opencode]="$HOME/.local/bin|$HOME/.opencode"
TOOL_OWNERSHIP_ROOTS[pi]="$HOME/.local/bin|$HOME/.pi/agent/install"
TOOL_UPDATE_CONTRACT[eget]="staged-release"
TOOL_UPDATE_CONTRACT[neovim]="staged-release"
TOOL_UPDATE_CONTRACT[tmux]="staged-build"
TOOL_UPDATE_CONTRACT[nvm]="vendor-installer-preserve-existing"
TOOL_UPDATE_CONTRACT[rust]="vendor-installer-in-place"
TOOL_UPDATE_CONTRACT[claude]="moving-vendor-installer"
TOOL_UPDATE_CONTRACT[codex]="moving-vendor-installer-preserve-launcher"
TOOL_UPDATE_CONTRACT[opencode]="moving-vendor-installer"
TOOL_UPDATE_CONTRACT[pi]="npm-prefix-in-place"
TOOL_UPDATE_CONTRACT[zsh]="apt-in-place"
TOOL_UPDATE_CONTRACT[docker]="apt-in-place"
TOOL_UPDATE_CONTRACT[azure-cli]="apt-in-place"
TOOL_UPDATE_CONTRACT[xrdp]="apt-and-service-in-place"

# TOOL_VERIFY: tool name → verification command (exit 0 = pass)
# Empty = use "command -v TOOL_BINARY[name]"
declare -A TOOL_VERIFY=(
    [nvm]='test -s "$HOME/.nvm/nvm.sh"'
    [rust]='command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1'
    [codex]='command -v codex >/dev/null 2>&1 && codex --version >/dev/null 2>&1'
    # pi is a node script, not a native binary — a present-but-broken node (or a
    # dangling symlink into ~/.pi/agent/install) still passes `command -v`.
    [pi]='command -v pi >/dev/null 2>&1 && pi --version >/dev/null 2>&1'
    # Binary present isn't success for a service — it must be running.
    [xrdp]='systemctl is-active --quiet xrdp 2>/dev/null'
    [ripgrep]='p=$(command -v rg 2>/dev/null || true); [[ -n "$p" && "$p" != */.codex/* && "$p" != */.vscode*/extensions/* ]]'
)

# TOOL_PATHS: tool name → space-separated paths to remove on uninstall
# Empty = managed by install method (apt uses apt remove; eget uses ~/.local/bin/BINARY)
declare -A TOOL_PATHS=(
    [neovim]="$HOME/.local/bin/nvim|$HOME/.local/nvim"
    [tmux]="$HOME/.local/bin/tmux"
    [nvm]="$HOME/.nvm"
    [rust]=""
    [uv]="$HOME/.local/bin/uv|$HOME/.local/bin/uvx"
    [claude]="$HOME/.local/bin/claude|$HOME/.local/share/claude"
    [codex]="$HOME/.local/bin/codex|$HOME/.codex/packages/standalone"
    [opencode]="$HOME/.local/bin/opencode|$HOME/.opencode"
    # Only the install/ subtree — ~/.pi/agent also holds settings.json,
    # sessions/, trust.json and models.json, which are user data.
    [pi]="$HOME/.local/bin/pi|$HOME/.pi/agent/install"
)

# TOOL_REMOVAL_INSTRUCTIONS: tool name → human-readable removal steps
# Only for tools that need manual steps beyond path deletion.
declare -A TOOL_REMOVAL_INSTRUCTIONS=(
    [rust]="Run 'rustup self uninstall' after separately backing up any Cargo credentials/configuration."
    [claude]="$HOME/.claude configuration and sessions are preserved"
    [codex]="$HOME/.codex configuration and sessions outside packages/standalone are preserved"
    [opencode]="$HOME/.config/opencode configuration is preserved"
    [pi]="$HOME/.pi/agent settings, trust data, and sessions outside install/ are preserved"
    [xrdp]="sudo systemctl disable --now xrdp && sudo apt remove xrdp xorgxrdp  # config backups: /etc/xrdp/xrdp.ini.dotfiles-bak*, ~/.xsession.dotfiles-bak*"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

# List tool names for a given tier, sorted.
# Usage: tools_for_tier "bash"  →  prints one tool name per line
tools_for_tier() {
    local tier="$1"
    local name
    for name in "${!TOOL_TIER[@]}"; do
        [[ "${TOOL_TIER[$name]}" == "$tier" ]] && printf '%s\n' "$name"
    done | sort
}

# Return the verification command for a tool.
# Falls back to "command -v <binary>" if no custom verify is defined.
tool_verify_command() {
    local name="$1"
    if [[ -n "${TOOL_VERIFY[$name]:-}" ]]; then
        echo "${TOOL_VERIFY[$name]}"
    else
        echo "command -v ${TOOL_BINARY[$name]} >/dev/null 2>&1"
    fi
}

# Return the uninstall paths for a tool (expanded).
# Falls back to ~/.local/bin/<binary> for eget tools.
tool_uninstall_paths() {
    local name="$1"
    if [[ -n "${TOOL_PATHS[$name]:-}" ]]; then
        printf '%s\n' "${TOOL_PATHS[$name]}" | tr '|' '\n'
    elif [[ "${TOOL_METHOD[$name]}" == "eget" ]]; then
        echo "$HOME/.local/bin/${TOOL_BINARY[$name]}"
    fi
}

tool_platform() {
    if [[ -n "${DOTFILES_TEST_PLATFORM:-}" ]]; then
        printf '%s\n' "$DOTFILES_TEST_PLATFORM"
    elif is_wsl; then
        printf 'wsl\n'
    else
        printf 'ubuntu\n'
    fi
}

tool_arch() {
    [[ -n "${DOTFILES_TEST_ARCH:-}" ]] && printf '%s\n' "$DOTFILES_TEST_ARCH" || get_arch
}

tool_applicable() {
    local name="$1" platform arch
    platform="$(tool_platform)"; arch="$(tool_arch)" || return 1
    case ",${TOOL_ARCHES[$name]:-}," in *",$arch,"*) ;; *) return 1 ;; esac
    case "${TOOL_PLATFORM[$name]:-ubuntu}" in
        ubuntu) [[ "$platform" == ubuntu || "$platform" == wsl ]] ;;
        wsl) [[ "$platform" == wsl ]] ;;
        *) return 1 ;;
    esac
}

tool_owned_path() {
    local name="$1" path="$2" roots root path_canon root_canon
    path_canon="$(realpath -m -- "$path" 2>/dev/null || true)"
    [[ -n "$path_canon" ]] || return 1
    roots="${TOOL_OWNERSHIP_ROOTS[$name]:-}"
    while [[ -n "$roots" ]]; do
        case "$roots" in *'|'*) root="${roots%%|*}"; roots="${roots#*|}" ;; *) root="$roots"; roots="" ;; esac
        root_canon="$(realpath -m -- "$root" 2>/dev/null || true)"
        [[ "$path_canon" == "$root_canon" || "$path_canon" == "$root_canon/"* ]] && return 0
    done
    return 1
}
