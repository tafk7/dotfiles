#!/bin/bash

# OpenAI Codex CLI: prefer the bundled binary from the openai.chatgpt VS Code
# extension, fall back to a standalone `codex` on PATH. Codex isn't installed
# by setup.sh — install via the VS Code extension or `npm i -g @openai/codex`.
_codex_resolve_bin() {
    # VS Code "ChatGPT - Codex" extension (WSL or remote SSH)
    local vscode_bin
    local vscode_root="$HOME/.vscode-server/extensions"
    if [[ -d "$vscode_root" ]]; then
        vscode_bin=$(find "$vscode_root" \
            -path "*/openai.chatgpt-*-linux-x64/bin/linux-x86_64/codex" \
            -type f -perm -111 2>/dev/null | sort -V | tail -1)
    fi
    if [[ -n "$vscode_bin" ]]; then
        echo "$vscode_bin"
        return
    fi

    # Standalone CLI on PATH
    local standalone
    standalone=$(type -P codex 2>/dev/null)
    if [[ -n "$standalone" && -x "$standalone" ]]; then
        echo "$standalone"
        return
    fi
    return 1
}

_CODEX_BIN=$(_codex_resolve_bin)
if [[ -n "$_CODEX_BIN" ]]; then
    # CODEX_FLAGS intentionally unquoted — allows multiple space-separated flags
    codex() { "$_CODEX_BIN" ${CODEX_FLAGS:-} "$@"; }
else
    codex() {
        echo "Codex CLI not found." >&2
        echo "  VS Code: install the 'openai.chatgpt' extension" >&2
        echo "  CLI: npm i -g @openai/codex" >&2
        return 1
    }
fi
unset -f _codex_resolve_bin

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
