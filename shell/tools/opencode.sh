#!/bin/bash

# opencode: whatever `opencode` is on PATH. The wrapper adds $OPENCODE_FLAGS
# and a helpful message when it's absent.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
unset -f opencode 2>/dev/null

_OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
[[ -n "$_OPENCODE_BIN" && -x "$_OPENCODE_BIN" ]] || _OPENCODE_BIN=""

if [[ -n "$_OPENCODE_BIN" ]]; then
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        opencode() { command opencode ${=OPENCODE_FLAGS} "$@"; }
    else
        opencode() {
            local -a flags=()
            read -r -a flags <<< "${OPENCODE_FLAGS:-}"
            command opencode "${flags[@]}" "$@"
        }
    fi
else
    opencode() {
        echo "opencode not found." >&2
        echo "  CLI: ./setup.sh --opencode  (official installer into ~/.local/bin)" >&2
        return 1
    }
fi
unset _OPENCODE_BIN

# No `occ` peer to `clc`: opencode's --continue exists only on subcommands (run,
# attach); interactive continuation is the in-TUI /continue command.
alias oc='opencode'                    # Launch the TUI (new session)
alias ocr='opencode run'               # One-off prompt (non-interactive)
alias ocrc='opencode run --continue'   # One-off prompt, continuing the last session
