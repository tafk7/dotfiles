#!/bin/bash

# Claude Code: the native CLI on PATH (installed by `./setup.sh --ai`, normally
# ~/.local/bin/claude). The wrapper exists solely to inject $CLAUDE_FLAGS.
#
# The VS Code extension binary is deliberately NOT discovered any more. Locating
# it meant a `find` across ~13k files under ~/.vscode-server/extensions on every
# single shell start (~126ms) to resolve a path that changes only when the
# extension updates.

# Re-source safety: drop our own function so `command -v` resolves the PATH
# binary, not the wrapper. `command -v` is portable across bash and zsh; `type -P`
# is bash-only (zsh errors "bad option: -P", silently yielding no match).
unset -f claude claude-vsc 2>/dev/null

# `command -v` as a bare condition is a builtin — no subshell, no fork. Capturing
# it (`x=$(command -v ...)`) would fork, which is what this file used to do.
if command -v claude >/dev/null 2>&1; then
    # `command` bypasses this function and runs the PATH binary.
    #
    # CLAUDE_FLAGS is intentionally split into separate arguments. zsh does NOT
    # word-split unquoted parameter expansions, so the shared `${CLAUDE_FLAGS:-}`
    # form silently passed a multi-flag CLAUDE_FLAGS to claude as a SINGLE
    # argument under zsh while working under bash. ${=VAR} forces the split;
    # keep the two branches in sync.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        claude() { command claude ${=CLAUDE_FLAGS} "$@"; }
    else
        claude() {
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
