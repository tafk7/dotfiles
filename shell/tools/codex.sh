#!/bin/bash

# OpenAI Codex CLI resolution: prefer the standalone native binary (installed by
# `./setup.sh --dev` — native musl build via eget, pinned in eget.toml), fall
# back to the bundled binary from the openai.chatgpt VS Code extension. Both are
# discovered once at init; the active one is chosen at call time. Set
# CODEX_USE_VSCODE=1 (exported, or inline) to make the extension binary primary,
# or call `codex-vsc` to invoke it explicitly regardless of the default.

# Standalone `codex` on PATH (native install). `type -P` ignores the codex()
# function defined below and searches PATH only.
_CODEX_STANDALONE=$(type -P codex 2>/dev/null)

# VS Code "ChatGPT - Codex" extension binary (WSL / remote SSH)
_CODEX_VSCODE=""
if [[ -d "$HOME/.vscode-server/extensions" ]]; then
    _CODEX_VSCODE=$(find "$HOME/.vscode-server/extensions" \
        -path "*/openai.chatgpt-*-linux-x64/bin/linux-x86_64/codex" \
        -type f -perm -111 2>/dev/null | sort -V | tail -1)
fi

# Default = native when present, else the extension binary.
if [[ -n "$_CODEX_STANDALONE" ]]; then
    _CODEX_DEFAULT="$_CODEX_STANDALONE"
else
    _CODEX_DEFAULT="$_CODEX_VSCODE"
fi
unset _CODEX_STANDALONE

if [[ -n "$_CODEX_DEFAULT" ]]; then
    # Choose at call time so CODEX_USE_VSCODE works inline, without re-scanning.
    codex() {
        local bin="$_CODEX_DEFAULT"
        [[ "${CODEX_USE_VSCODE:-0}" == "1" && -n "$_CODEX_VSCODE" ]] && bin="$_CODEX_VSCODE"
        # CODEX_FLAGS intentionally unquoted — allows multiple space-separated flags
        "$bin" ${CODEX_FLAGS:-} "$@"
    }
else
    codex() {
        echo "Codex CLI not found." >&2
        echo "  CLI:     ./setup.sh --dev  (native binary via eget)" >&2
        echo "  VS Code: install the 'openai.chatgpt' extension" >&2
        return 1
    }
fi

# Explicit handle to the VS Code extension binary, independent of the default.
# Defined only when that binary is present.
if [[ -n "$_CODEX_VSCODE" ]]; then
    codex-vsc() { "$_CODEX_VSCODE" ${CODEX_FLAGS:-} "$@"; }
fi

# Codex CLI shortcuts
alias cx='codex'                       # New session
alias cxr='codex resume'               # Resume (picker)
alias cxc='codex resume --last'        # Continue last session
alias cxp='codex exec'                 # One-off prompt (non-interactive)

# Codex with alternate config dir at ~/.codex-alt (CODEX_HOME override)
alias cxh='CODEX_HOME="$HOME/.codex-alt" codex'
alias cxhr='CODEX_HOME="$HOME/.codex-alt" codex resume'
alias cxhc='CODEX_HOME="$HOME/.codex-alt" codex resume --last'
alias cxhp='CODEX_HOME="$HOME/.codex-alt" codex exec'
