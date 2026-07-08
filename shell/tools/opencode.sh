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
        # opencode's OpenTelemetry (experimental.openTelemetry) exports via OTLP-HTTP.
        # Pin the exporter to localhost — scoped to this process, not the global env —
        # so traces never leave the box unless you deliberately point it at an internal
        # collector. No collector listening? It just no-ops (refused/dropped), zero egress.
        # OPENCODE_FLAGS intentionally unquoted — allows multiple space-separated flags
        OTEL_EXPORTER_OTLP_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}" \
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

# opencode shortcuts. Note: opencode's interactive "continue last session" is an
# in-TUI command (/continue or /sessions), NOT a top-level CLI flag — so there's
# no `occ` peer to claude's `clc`. --continue exists only on subcommands (run,
# attach), hence the run-continue alias below.
alias oc='opencode'                    # Launch the TUI (new session)
alias ocr='opencode run'               # One-off prompt (non-interactive)
alias ocrc='opencode run --continue'   # One-off prompt, continuing the last session
