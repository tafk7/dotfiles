#!/bin/bash
# Install Claude Code via the official native installer (claude.ai/install.sh).
#
# Ensure the native binary exists. bin/ai-update claude explicitly updates it
# using --force; automatic updates may be disabled by the configured traffic policy.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# The native installer writes the binary here. Verify by absolute path, since
# ~/.local/bin may not be on PATH yet on a fresh machine.
CLAUDE_BIN="$HOME/.local/bin/claude"

# Reconcile portable keys and assets; all backups stay in the application home.
provision_claude_settings() {
    "$DOTFILES_DIR/bin/ai-config" claude
}

# Install the agent-badge plugin (plugins/agent-badge-claude) from this repo,
# which is also a marketplace (.claude-plugin/marketplace.json). Registered as a
# local directory so it tracks the working tree and needs no network. Both
# commands are idempotent. Never fatal: the badge is a convenience.
provision_agent_badge_plugin() {
    [[ "${DOTFILES_AGENT_BADGE_ENABLED:-1}" == "1" ]] || {
        log "Agent-badge disabled; skipping plugin registration."
        return 0
    }
    local claude_cmd="${1:-}"
    [[ -n "$claude_cmd" && -x "$claude_cmd" ]] || claude_cmd="$(command -v claude 2>/dev/null || true)"
    [[ -n "$claude_cmd" ]] || return 0
    [[ -f "$DOTFILES_DIR/.claude-plugin/marketplace.json" ]] || return 0

    if ! "$claude_cmd" plugin marketplace add "$DOTFILES_DIR" >/dev/null 2>&1; then
        warn "Could not register $DOTFILES_DIR as a plugin marketplace; skipping agent-badge."
        return 0
    fi
    if "$claude_cmd" plugin install agent-badge@tafk7 >/dev/null 2>&1; then
        success "Plugin agent-badge installed (tmux window badges for agent sessions)."
        if [[ -n "${TMUX:-}" ]]; then
            "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" wire >/dev/null 2>&1 || true
        fi
        log "  Takes effect in new Claude sessions."
    else
        warn "Could not install the agent-badge plugin; see plugins/agent-badge-claude/README.md."
    fi
}

provision_claude_settings

if [[ "$FORCE" != true && -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code already installed ($("$CLAUDE_BIN" --version 2>/dev/null | head -n1)); updates follow its traffic policy; use bin/ai-update claude."
    provision_agent_badge_plugin "$CLAUDE_BIN"
    exit 2
fi

# Don't shadow an externally managed Claude: ~/.local/bin comes first on PATH.
EXTERNAL_CLAUDE="$(command -v claude 2>/dev/null || true)"
if [[ -n "$EXTERNAL_CLAUDE" && "$EXTERNAL_CLAUDE" != "$CLAUDE_BIN" ]]; then
    warn "Found an externally-managed claude on PATH: $EXTERNAL_CLAUDE"
    warn "Skipping install to avoid a shadow copy at $CLAUDE_BIN."
    warn "Move/remove the external installation explicitly before installing a dotfiles-owned copy."
    # Still a working Claude, so still worth the plugin.
    provision_agent_badge_plugin "$EXTERNAL_CLAUDE"
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
if ! env PROFILE=/dev/null bash "$claude_installer"; then
    [[ "$downloaded_installer" == true ]] && rm -f "$claude_installer"
    error "Claude Code installation failed"
    exit 1
fi
[[ "$downloaded_installer" == true ]] && rm -f "$claude_installer"

if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "The Claude installer modified a shell rc file that is symlinked into the repo."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted — PATH is already set by shell/env.sh)"
fi

if [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code installed: $("$CLAUDE_BIN" --version 2>/dev/null | head -n1)"
    provision_agent_badge_plugin "$CLAUDE_BIN"
    exit 0
fi

error "Claude Code installer ran but $CLAUDE_BIN is not runnable"
exit 1
