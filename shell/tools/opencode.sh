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
        # Resolve via PATH at call time (`command` bypasses this function) rather
        # than capturing $_OPENCODE_BIN — it's unset just below, so a captured
        # reference would expand to "" and try to run the empty string.
        # OPENCODE_FLAGS intentionally unquoted — allows multiple space-separated flags
        command opencode ${OPENCODE_FLAGS:-} "$@"
    }
else
    opencode() {
        echo "opencode not found." >&2
        echo "  CLI: ./setup.sh --opencode  (official installer into ~/.local/bin)" >&2
        return 1
    }
fi
unset _OPENCODE_BIN

# opencode shortcuts. Note: opencode's interactive "continue last session" is an
# in-TUI command (/continue or /sessions), NOT a top-level CLI flag — so there's
# no `occ` peer to claude's `clc`. --continue exists only on subcommands (run,
# attach), hence the run-continue alias below.
alias oc='opencode'                    # Launch the TUI (new session)
alias ocr='opencode run'               # One-off prompt (non-interactive)
alias ocrc='opencode run --continue'   # One-off prompt, continuing the last session
