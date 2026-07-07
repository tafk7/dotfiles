#!/bin/bash
# Install the OpenAI Codex CLI (native musl build) via eget, pinned in eget-ai.toml.
#
# Codex is an "ai" tier tool (./setup.sh --ai, or --full). It is kept out of the
# shell-tier `eget --download-all` batch so an org-managed Codex install isn't
# shadowed by default. Re-run with --force to reinstall (e.g. after a version bump
# in eget-ai.toml, or to repair a broken binary).
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# eget renames the archive's binary to plain `codex` at this absolute path
# (see eget-ai.toml). Verify by absolute path: on a fresh machine ~/.local/bin
# is not guaranteed to be on the installer process's PATH.
CODEX_BIN="$HOME/.local/bin/codex"
AI_CONFIG="${DOTFILES_DIR:-$HOME/dotfiles}/eget-ai.toml"

if [[ "$FORCE" != true && -x "$CODEX_BIN" ]] && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex already installed ($("$CODEX_BIN" --version 2>/dev/null | head -n1))."
    exit 2
fi

# Don't shadow an externally-managed Codex (same reasoning as install-claude.sh).
EXTERNAL_CODEX="$(command -v codex 2>/dev/null || true)"
if [[ "$FORCE" != true && -n "$EXTERNAL_CODEX" && "$EXTERNAL_CODEX" != "$CODEX_BIN" ]]; then
    warn "Found an externally-managed codex on PATH: $EXTERNAL_CODEX"
    warn "Skipping install to avoid a shadow copy at $CODEX_BIN."
    warn "Re-run with --force to install the dotfiles-managed copy anyway."
    exit 2
fi

if [[ ! -f "$AI_CONFIG" ]]; then
    error "eget-ai.toml not found at $AI_CONFIG"
    exit 1
fi

# Codex is fetched with eget. eget lives in the shell tier, but --ai can run
# without --shell, so ensure it is present first.
eget_bin="$HOME/.local/bin/eget"
command -v eget >/dev/null 2>&1 && eget_bin="$(command -v eget)"
if [[ ! -x "$eget_bin" ]]; then
    log "eget not found; installing it first (needed to fetch Codex)..."
    rc=0
    "${DOTFILES_DIR:-$HOME/dotfiles}/installers/install-eget.sh" || rc=$?
    # install-eget.sh exits 2 when already up to date; only non-{0,2} is a failure.
    if [[ "$rc" != 0 && "$rc" != 2 ]]; then
        error "eget installation failed; cannot install Codex"
        exit 1
    fi
    command -v eget >/dev/null 2>&1 && eget_bin="$(command -v eget)"
    if [[ ! -x "$eget_bin" ]]; then
        error "eget not found at $eget_bin after install"
        exit 1
    fi
fi

# Under --force, clear the existing binary so eget re-downloads it.
[[ "$FORCE" == true ]] && rm -f "$CODEX_BIN"

log "Installing Codex via eget (pinned in eget-ai.toml)..."
if ! EGET_CONFIG="$AI_CONFIG" "$eget_bin" --download-all; then
    error "Codex installation failed"
    exit 1
fi

if [[ -x "$CODEX_BIN" ]] && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex installed: $("$CODEX_BIN" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "Codex installer ran but $CODEX_BIN is not runnable"
exit 1
