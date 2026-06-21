#!/bin/bash

# Claude Code resolution: prefer the standalone native CLI (~/.local/bin/claude),
# fall back to the VS Code extension's bundled binary. Both are discovered once at
# init; the active one is chosen at call time. Set CLAUDE_USE_VSCODE=1 (exported,
# or inline as `CLAUDE_USE_VSCODE=1 claude ...`) to make the extension binary
# primary, or call `claude-vsc` to invoke it explicitly regardless of the default.

# Re-source safety: drop our own functions so `command -v` resolves the PATH
# binary, not the wrapper. `command -v` is portable across bash and zsh; `type -P`
# is bash-only (zsh errors "bad option: -P", silently yielding no match).
unset -f claude claude-vsc 2>/dev/null

# Standalone `claude` on PATH (native install at ~/.local/bin/claude).
_CLAUDE_STANDALONE=$(command -v claude 2>/dev/null || true)
[[ -n "$_CLAUDE_STANDALONE" && -x "$_CLAUDE_STANDALONE" ]] || _CLAUDE_STANDALONE=""

# VS Code "Claude Code" extension binary (WSL / remote SSH)
_CLAUDE_VSCODE=""
if [[ -d "$HOME/.vscode-server/extensions" ]]; then
    _CLAUDE_VSCODE=$(find "$HOME/.vscode-server/extensions" \
        -path "*/anthropic.claude-code-*-linux-x64/resources/native-binary/claude" \
        -type f -perm -111 2>/dev/null | sort -V | tail -1)
fi

# Default = native when present, else the extension binary.
if [[ -n "$_CLAUDE_STANDALONE" ]]; then
    _CLAUDE_DEFAULT="$_CLAUDE_STANDALONE"
else
    _CLAUDE_DEFAULT="$_CLAUDE_VSCODE"
fi
unset _CLAUDE_STANDALONE

if [[ -n "$_CLAUDE_DEFAULT" ]]; then
    # Choose at call time so CLAUDE_USE_VSCODE works inline, without re-scanning.
    claude() {
        local bin="$_CLAUDE_DEFAULT"
        [[ "${CLAUDE_USE_VSCODE:-0}" == "1" && -n "$_CLAUDE_VSCODE" ]] && bin="$_CLAUDE_VSCODE"
        # CLAUDE_FLAGS intentionally unquoted — allows multiple space-separated flags
        "$bin" ${CLAUDE_FLAGS:-} "$@"
    }
else
    claude() {
        echo "Claude Code not found." >&2
        echo "  CLI:     ./setup.sh --dev  (native installer)" >&2
        echo "  VS Code: install the 'anthropic.claude-code' extension" >&2
        return 1
    }
fi

# Explicit handle to the VS Code extension binary, independent of the default.
# Defined only when that binary is present.
if [[ -n "$_CLAUDE_VSCODE" ]]; then
    claude-vsc() { "$_CLAUDE_VSCODE" ${CLAUDE_FLAGS:-} "$@"; }
fi

# Clean Claude Code shell snapshots (fixes zoxide issues)
alias clean-claude-snapshots='rm -rf ~/.claude/shell-snapshots/ ~/.zcompdump* && echo "Cleaned Claude snapshots and zsh cache"'

# Claude CLI shortcuts
alias cl='claude'                # New session
alias clc='claude --continue'    # Continue last session
alias clp='claude --print'       # One-off command (non-interactive)

# Claude local-only (no global settings)
alias cll='claude --setting-sources project,local'
alias cllc='claude --setting-sources project,local --continue'
alias cllp='claude --setting-sources project,local --print'

# Clara: alternate global config dir at ~/.clara (CLAUDE_CONFIG_DIR override)
alias clara='CLAUDE_CONFIG_DIR="$HOME/.clara" claude'
alias clarac='CLAUDE_CONFIG_DIR="$HOME/.clara" claude --continue'
alias clarap='CLAUDE_CONFIG_DIR="$HOME/.clara" claude --print'
