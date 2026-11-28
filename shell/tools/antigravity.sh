#!/bin/bash

# Antigravity's CLI: whatever `agy` is on PATH, so a machine's own launcher
# earlier on PATH stays in front. The wrapper refuses `agy update` and
# `agy install` (dotfiles upgrade antigravity updates it; `agy install` edits
# the shell profile), and says how to install agy when it is absent.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
unset -f agy 2>/dev/null

if command -v agy >/dev/null 2>&1; then
    agy() {
        case "${1:-}" in
            update|install)
                echo "agy $1: not from here. dotfiles upgrade antigravity updates agy, without touching the shell profile." >&2
                return 64
                ;;
        esac
        command agy "$@"
    }
else
    agy() {
        echo "agy not found. Install with: ./setup.sh --antigravity" >&2
        return 1
    }
fi
