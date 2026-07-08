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
    [sd]=sd
    [shellcheck]=shellcheck
    [neovim]=nvim
    [tmux]=tmux
    [plantuml]=plantuml
    [nvm]=nvm
    [claude]=claude
    [codex]=codex
    [opencode]=opencode
    [wsl2-ssh-agent]=wsl2-ssh-agent
    [xrdp]=xrdp
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
    [sd]=eget
    [shellcheck]=eget
    [neovim]=installer
    [tmux]=installer
    [plantuml]=installer
    [nvm]=installer
    [claude]=installer
    [codex]=installer
    [opencode]=installer
    [wsl2-ssh-agent]=eget
    [xrdp]=installer
)

# TOOL_TIER: tool name → tier (shell|dev|work|ai|rdp)
# "ai" and "rdp" are orthogonal to the cumulative shell→dev→work chain: those
# tools install only under their own flag, never as a side effect of a tier.
# --full implies ai but NOT rdp (a tier must never silently open a listener).
declare -A TOOL_TIER=(
    [starship]=shell  [eza]=shell     [fzf]=shell      [zoxide]=shell
    [delta]=shell     [btop]=shell    [glow]=shell      [lazygit]=shell
    [uv]=shell        [bat]=shell     [fd]=shell        [ripgrep]=shell
    [direnv]=shell    [eget]=shell    [sd]=shell
    [neovim]=dev      [tmux]=dev      [plantuml]=dev   [shellcheck]=dev
    [wsl2-ssh-agent]=dev
    [claude]=ai       [codex]=ai       [opencode]=ai
    [xrdp]=rdp
    [nvm]=work
)

# TOOL_VERIFY: tool name → verification command (exit 0 = pass)
# Empty = use "command -v TOOL_BINARY[name]"
declare -A TOOL_VERIFY=(
    [nvm]='test -s "$HOME/.nvm/nvm.sh"'
    # Binary present isn't success for a service — it must be running.
    [xrdp]='systemctl is-active --quiet xrdp 2>/dev/null'
)

# TOOL_PATHS: tool name → space-separated paths to remove on uninstall
# Empty = managed by install method (apt uses apt remove; eget uses ~/.local/bin/BINARY)
declare -A TOOL_PATHS=(
    [neovim]="\$HOME/.local/bin/nvim \$HOME/.local/nvim"
    [nvm]="\$HOME/.nvm"
    [uv]="\$HOME/.local/bin/uv \$HOME/.local/bin/uvx"
    [claude]="\$HOME/.local/bin/claude \$HOME/.local/share/claude"
    [codex]="\$HOME/.local/bin/codex"
    [opencode]="\$HOME/.local/bin/opencode \$HOME/.opencode"
)

# TOOL_REMOVAL_INSTRUCTIONS: tool name → human-readable removal steps
# Only for tools that need manual steps beyond path deletion.
declare -A TOOL_REMOVAL_INSTRUCTIONS=(
    [nvm]="rm -rf \$HOME/.nvm  # then restart shell"
    [claude]="rm -rf \$HOME/.local/share/claude  # ~/.claude config/sessions are preserved"
    [codex]="rm -f \$HOME/.local/bin/codex  # ~/.codex config/sessions are preserved"
    [opencode]="rm -f \$HOME/.local/bin/opencode  # ~/.config/opencode config is preserved"
    [xrdp]="sudo systemctl disable --now xrdp && sudo apt remove xrdp xorgxrdp  # config backups: /etc/xrdp/xrdp.ini.dotfiles-bak*, ~/.xsession.dotfiles-bak*"
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
