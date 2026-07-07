#!/bin/bash

# opencode CLI resolution: the native binary on PATH (installed by
# `./setup.sh --opencode` into ~/.local/bin, or provided by an org). Unlike
# Claude Code / Codex, opencode ships no VS Code-bundled binary to fall back to,
# so resolution is a straight PATH lookup — the wrapper just adds flag pass-through
# and a helpful message when it's absent.

# Re-source safety: drop our own function so `command -v` resolves the PATH
# binary, not the wrapper. `command -v` is portable across bash and zsh.
unset -f opencode 2>/dev/null

_OPENCODE_BIN=$(command -v opencode 2>/dev/null || true)
[[ -n "$_OPENCODE_BIN" && -x "$_OPENCODE_BIN" ]] || _OPENCODE_BIN=""

if [[ -n "$_OPENCODE_BIN" ]]; then
    opencode() {
        # OPENCODE_FLAGS intentionally unquoted — allows multiple space-separated flags
        "$_OPENCODE_BIN" ${OPENCODE_FLAGS:-} "$@"
    }
else
    opencode() {
        echo "opencode not found." >&2
        echo "  CLI: ./setup.sh --opencode  (official installer into ~/.local/bin)" >&2
        return 1
    }
fi
unset _OPENCODE_BIN

# opencode shortcuts
alias oc='opencode'          # Launch the TUI
alias ocr='opencode run'     # One-off prompt (non-interactive)
