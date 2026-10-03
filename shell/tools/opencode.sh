#!/bin/bash

# opencode: whatever `opencode` is on PATH. The wrapper adds $OPENCODE_FLAGS
# and a helpful message when it's absent.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
unset -f opencode 2>/dev/null

_OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
[[ -n "$_OPENCODE_BIN" && -x "$_OPENCODE_BIN" ]] || _OPENCODE_BIN=""

if [[ -n "$_OPENCODE_BIN" ]]; then
    opencode() {
        local -a flags=()
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            # Zsh explicit splitting, without eval.
            # shellcheck disable=SC2206
            flags=(${=OPENCODE_FLAGS})
        else
            read -r -a flags <<< "${OPENCODE_FLAGS:-}"
        fi
        case "${1:-}" in
            run|mini)
                local subcommand="$1"
                shift
                command opencode "$subcommand" "${flags[@]}" "$@"
                ;;
            upgrade|update|uninstall|service|debug|auth|models|session|plugin|mcp|api|serve|pair|stats|acp|reload|--help|-h|--version|-v)
                command opencode "$@" ;;
            *) command opencode "${flags[@]}" "$@" ;;
        esac
    }
else
    opencode() {
        echo "opencode not found." >&2
        echo "  CLI: ./setup.sh --opencode  (official installer into ~/.local/bin)" >&2
        return 1
    }
fi
unset _OPENCODE_BIN

# V2 also accepts `opencode --continue` for interactive continuation.
# OPENCODE_FLAGS must be valid for the invoked interface; model flags belong to run/mini.
alias oc='opencode'                    # Launch the TUI (new session)
alias ocr='opencode run'               # One-off prompt (non-interactive)
alias ocrc='opencode run --continue'   # One-off prompt, continuing the last session
