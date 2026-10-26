#!/bin/bash
# Install Claude Code via the official native installer (claude.ai/install.sh).
#
# Ensure the native binary exists. bin/ai-update claude explicitly updates it
# using --force; automatic updates may be disabled by the configured traffic policy.
# Settings and the agent-badge plugin are configure steps (lib/configure.sh),
# which setup runs whether or not this installed anything.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component claude; exit; fi

FORCE=false
# --update (setup --upgrade) runs the official installer as --force does.
[[ "${1:-}" == "--force" || "${1:-}" == "--update" ]] && FORCE=true

# The native installer writes the binary here. Verify by absolute path, since
# ~/.local/bin may not be on PATH yet on a fresh machine.
CLAUDE_BIN="$HOME/.local/bin/claude"

if [[ "$FORCE" != true && -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code already installed ($("$CLAUDE_BIN" --version 2>/dev/null | head -n1)); updates follow its traffic policy; use bin/ai-update claude."
    exit 2
fi

# Don't shadow an externally managed Claude: ~/.local/bin comes first on PATH.
EXTERNAL_CLAUDE="$(command -v claude 2>/dev/null || true)"
if [[ -n "$EXTERNAL_CLAUDE" && "$EXTERNAL_CLAUDE" != "$CLAUDE_BIN" ]]; then
    warn "Found an externally-managed claude on PATH: $EXTERNAL_CLAUDE"
    warn "Skipping install to avoid a shadow copy at $CLAUDE_BIN."
    warn "Move/remove the external installation explicitly before installing a dotfiles-owned copy."
    exit 2
fi

log "Installing Claude Code via claude.ai/install.sh..."

# The installer should skip editing rc files because ~/.local/bin is on PATH.
# They are symlinks into this repo, so warn if it wrote through anyway.
claude_installer="${DOTFILES_CLAUDE_INSTALLER_SCRIPT:-}"
downloaded_installer=false
if [[ -z "$claude_installer" ]]; then
    claude_installer="$(mktemp)"
    downloaded_installer=true
    download_installer_script https://claude.ai/install.sh "$claude_installer" || exit 1
elif [[ ! -s "$claude_installer" ]]; then
    error "DOTFILES_CLAUDE_INSTALLER_SCRIPT is missing or empty: $claude_installer"
    exit 1
fi
rc_before="$(rc_snapshot)"
if ! env PROFILE=/dev/null bash "$claude_installer"; then
    [[ "$downloaded_installer" == true ]] && rm -f "$claude_installer"
    error "Claude Code installation failed"
    exit 1
fi
[[ "$downloaded_installer" == true ]] && rm -f "$claude_installer"

warn_if_rc_changed "$rc_before" 'PATH is already set by shell/env.sh'

if [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code installed: $("$CLAUDE_BIN" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "Claude Code installer ran but $CLAUDE_BIN is not runnable"
exit 1
