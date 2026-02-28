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
    [glow]=glow
    [lazygit]=lazygit
    [uv]=uv
    [bat]=batcat
    [fd]=fdfind
    [ripgrep]=rg
    [direnv]=direnv
    [eget]=eget
    [neovim]=nvim
    [tmux]=tmux
    [plantuml]=plantuml
    [nvm]=nvm
    [pyenv]=pyenv
    [poetry]=poetry
)

# TOOL_METHOD: tool name → install method (eget|apt|installer|external)
declare -A TOOL_METHOD=(
    [starship]=eget
    [eza]=eget
    [fzf]=eget
    [zoxide]=eget
    [delta]=eget
    [btop]=eget
    [glow]=eget
    [lazygit]=eget
    [uv]=eget
    [bat]=apt
    [fd]=apt
    [ripgrep]=apt
    [direnv]=apt
    [eget]=installer
    [neovim]=installer
    [tmux]=installer
    [plantuml]=installer
    [nvm]=installer
    [pyenv]=installer
    [poetry]=installer
)

# TOOL_TIER: tool name → minimum tier (shell|dev|full)
declare -A TOOL_TIER=(
    [starship]=shell  [eza]=shell     [fzf]=shell      [zoxide]=shell
    [delta]=shell     [btop]=shell    [glow]=shell      [lazygit]=shell
    [uv]=shell        [bat]=shell     [fd]=shell        [ripgrep]=shell
    [direnv]=shell    [eget]=shell
    [neovim]=dev      [tmux]=dev      [plantuml]=dev
    [nvm]=full        [pyenv]=full    [poetry]=full
)

# TOOL_VERIFY: tool name → verification command (exit 0 = pass)
# Empty = use "command -v TOOL_BINARY[name]"
declare -A TOOL_VERIFY=(
    [nvm]='test -s "$HOME/.nvm/nvm.sh"'
    [pyenv]='test -d "$HOME/.pyenv"'
)

# TOOL_PATHS: tool name → space-separated paths to remove on uninstall
# Empty = managed by install method (apt uses apt remove; eget uses ~/.local/bin/BINARY)
declare -A TOOL_PATHS=(
    [neovim]="\$HOME/.local/bin/nvim \$HOME/.local/nvim"
    [nvm]="\$HOME/.nvm"
    [pyenv]="\$HOME/.pyenv"
    [poetry]="\$HOME/.local/bin/poetry"
    [uv]="\$HOME/.local/bin/uv \$HOME/.local/bin/uvx"
)

# TOOL_REMOVAL_INSTRUCTIONS: tool name → human-readable removal steps
# Only for tools that need manual steps beyond path deletion.
declare -A TOOL_REMOVAL_INSTRUCTIONS=(
    [nvm]="rm -rf \$HOME/.nvm  # then restart shell"
    [pyenv]="rm -rf \$HOME/.pyenv  # then restart shell"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

# List tool names for a given tier, sorted.
# Usage: tools_for_tier "shell"  →  prints one tool name per line
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
        eval echo "${TOOL_PATHS[$name]}"
    elif [[ "${TOOL_METHOD[$name]}" == "eget" ]]; then
        echo "$HOME/.local/bin/${TOOL_BINARY[$name]}"
    fi
}
