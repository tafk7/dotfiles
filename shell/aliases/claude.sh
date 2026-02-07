#!/bin/bash

# Claude Code: prefer VS Code extension binary, fall back to standalone CLI
_claude_resolve_bin() {
    # VS Code extension (WSL or remote SSH)
    local vscode_bin
    vscode_bin=$(ls -d ~/.vscode-server/extensions/anthropic.claude-code-*-linux-x64/resources/native-binary/claude 2>/dev/null | sort -V | tail -1)
    if [[ -n "$vscode_bin" && -x "$vscode_bin" ]]; then
        echo "$vscode_bin"
        return
    fi

    # Standalone CLI on PATH
    local standalone
    standalone=$(command -v claude 2>/dev/null)
    if [[ -n "$standalone" ]]; then
        echo "$standalone"
        return
    fi

    return 1
}

# Resolve once at shell init, define function that all aliases call through
_CLAUDE_BIN=$(_claude_resolve_bin)
if [[ -n "$_CLAUDE_BIN" ]]; then
    claude() { "$_CLAUDE_BIN" "$@"; }
fi
unset -f _claude_resolve_bin

# Clean Claude Code shell snapshots (fixes zoxide issues)
alias clean-claude-snapshots='rm -rf ~/.claude/shell-snapshots/ ~/.zcompdump* && echo "Cleaned Claude snapshots and zsh cache"'
