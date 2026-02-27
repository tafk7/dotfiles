#!/bin/bash

# Claude Code: prefer VS Code extension binary, fall back to standalone CLI
_claude_resolve_bin() {
    # VS Code extension (WSL or remote SSH)
    local vscode_bin
    local vscode_root="$HOME/.vscode-server/extensions"
    if [[ -d "$vscode_root" ]]; then
        vscode_bin=$(find "$vscode_root" \
            -path "*/anthropic.claude-code-*-linux-x64/resources/native-binary/claude" \
            -type f -perm -111 2>/dev/null | sort -V | tail -1)
    fi
    if [[ -n "$vscode_bin" ]]; then
        echo "$vscode_bin"
        return
    fi

    # Standalone CLI on PATH
    local standalone
    standalone=$(type -P claude 2>/dev/null)
    if [[ -n "$standalone" && -x "$standalone" ]]; then
        echo "$standalone"
        return
    fi

    return 1
}

# Resolve once at shell init, define function that all aliases call through
_CLAUDE_BIN=$(_claude_resolve_bin)
if [[ -n "$_CLAUDE_BIN" ]]; then
    # CLAUDE_FLAGS intentionally unquoted — allows multiple space-separated flags
    claude() { "$_CLAUDE_BIN" ${CLAUDE_FLAGS:-} "$@"; }
else
    claude() {
        echo "Claude Code not found." >&2
        echo "  VS Code: install the 'anthropic.claude-code' extension" >&2
        return 1
    }
fi
unset -f _claude_resolve_bin

# Clean Claude Code shell snapshots (fixes zoxide issues)
alias clean-claude-snapshots='rm -rf ~/.claude/shell-snapshots/ ~/.zcompdump* && echo "Cleaned Claude snapshots and zsh cache"'
