#!/bin/bash

# Claude Code: whatever `claude` is on PATH. The wrapper only injects
# $CLAUDE_FLAGS. The VS Code extension's bundled binary is deliberately not
# discovered; finding it cost a filesystem scan at every shell start.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
# `type -P` would be bash-only.
unset -f claude 2>/dev/null

# Claude only recognizes a subcommand as the first argument; behind injected
# flags, `claude stop <id>` becomes the prompt "stop <id>". `agents` is left
# out: it parses after flags and applies them to dispatched sessions.
_claude_is_subcommand() {
    case "${1:-}" in
        attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|\
        project|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade) return 0 ;;
    esac
    return 1
}

# A bare `command -v` condition doesn't fork; capturing its output would.
if command -v claude >/dev/null 2>&1; then
    # zsh doesn't word-split unquoted expansions, so ${=VAR} is needed to pass
    # CLAUDE_FLAGS as separate arguments. Keep both branches in sync.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        claude() {
            if _claude_is_subcommand "$@"; then command claude "$@"
            else command claude ${=CLAUDE_FLAGS} "$@"; fi
        }
    else
        claude() {
            _claude_is_subcommand "$@" && { command claude "$@"; return; }
            local -a flags=()
            read -r -a flags <<< "${CLAUDE_FLAGS:-}"
            command claude "${flags[@]}" "$@"
        }
    fi
else
    claude() {
        echo "Claude Code not found. Install with: ./setup.sh --ai" >&2
        return 1
    }
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
