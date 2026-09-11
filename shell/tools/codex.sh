#!/bin/bash

# OpenAI Codex CLI: the official standalone binary on PATH (installed by
# `./setup.sh --ai`, normally ~/.local/bin/codex). The wrapper exists solely to
# inject $CODEX_FLAGS.
#
# The openai.chatgpt VS Code extension binary is deliberately NOT discovered any
# more. Locating it meant a `find` across ~13k files under
# ~/.vscode-server/extensions on every single shell start (~127ms) to resolve a
# path that changes only when the extension updates.

# Re-source safety: drop our own function so `command -v` resolves the PATH
# binary, not the wrapper. `command -v` is portable across bash and zsh; `type -P`
# is bash-only (zsh errors "bad option: -P", silently yielding no match).
unset -f codex codex-vsc 2>/dev/null

# `command -v` as a bare condition is a builtin — no subshell, no fork. Capturing
# it (`x=$(command -v ...)`) would fork, which is what this file used to do.
if command -v codex >/dev/null 2>&1; then
    # CODEX_FLAGS is intentionally split into separate arguments. zsh does NOT
    # word-split unquoted parameter expansions, so the shared `${CODEX_FLAGS:-}`
    # form silently passed CODEX_FLAGS="--profile amd" to codex as a SINGLE
    # argument under zsh ("unexpected argument '--profile amd'") while working
    # under bash. ${=VAR} forces the split; keep the two branches in sync.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        codex() { command codex ${=CODEX_FLAGS} "$@"; }
    else
        codex() {
            local -a flags=()
            read -r -a flags <<< "${CODEX_FLAGS:-}"
            command codex "${flags[@]}" "$@"
        }
    fi
else
    codex() {
        echo "Codex CLI not found. Install with: ./setup.sh --ai" >&2
        return 1
    }
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
