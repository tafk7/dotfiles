#!/bin/bash

# Pi: whatever `pi` is on PATH. The wrapper only injects $PI_FLAGS. Pi is a
# Node package, so it needs Node >= 22.19 on PATH at call time.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
# `type -P` would be bash-only.
unset -f pi 2>/dev/null

if command -v pi >/dev/null 2>&1; then
    # zsh doesn't word-split unquoted expansions, so ${=VAR} is needed to pass
    # PI_FLAGS as separate arguments. Keep both branches in sync.
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        pi() { command pi ${=PI_FLAGS} "$@"; }
    else
        pi() {
            local -a flags=()
            read -r -a flags <<< "${PI_FLAGS:-}"
            command pi "${flags[@]}" "$@"
        }
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
