#!/bin/bash

# Pi (earendil-works/pi): the npm-installed CLI on PATH — `./setup.sh --pi`
# installs it into ~/.pi/agent/install and symlinks ~/.local/bin/pi. The wrapper
# exists solely to inject $PI_FLAGS.
#
# Unlike Claude Code / Codex / opencode, Pi is a Node package rather than a
# standalone binary, so it needs Node >= 22.19 on PATH at call time (NVM's
# ~/.nvm/default/bin, added by shell/env.sh).

# Re-source safety: drop our own function so `command -v` resolves the PATH
# binary, not the wrapper. `command -v` is portable across bash and zsh; `type -P`
# is bash-only (zsh errors "bad option: -P", silently yielding no match).
unset -f pi 2>/dev/null

# `command -v` as a bare condition is a builtin — no subshell, no fork.
if command -v pi >/dev/null 2>&1; then
    # `command` bypasses this function and runs the PATH binary.
    #
    # PI_FLAGS is intentionally split into separate arguments. zsh does NOT
    # word-split unquoted parameter expansions, so a shared `${PI_FLAGS:-}` form
    # would pass PI_FLAGS="--provider anthropic" as a SINGLE argument under zsh
    # while working under bash. ${=VAR} forces the split; keep the branches in sync.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        pi() { command pi ${=PI_FLAGS} "$@"; }
    else
        pi() { command pi ${PI_FLAGS:-} "$@"; }
    fi
else
    pi() {
        echo "Pi not found. Install with: ./setup.sh --pi" >&2
        echo "  (needs Node >= 22.19 — ./setup.sh --work provides it via NVM)" >&2
        return 1
    }
fi

# Pi shortcuts. No print alias: the obvious `pip` would shadow Python's pip, and
# `pi -p` is already short. `pi` itself is the new-session entry point.
alias pic='pi -c'    # Continue most recent session
alias pir='pi -r'    # Browse and select a past session
