#!/bin/bash
# Install or update the OpenAI Codex CLI with OpenAI's standalone installer.
#
# A normal rerun preserves a working standalone install; --force asks the
# official installer to update or repair it without deleting its launcher.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# The official standalone installer owns this launcher and the release tree
# under ~/.codex/packages/standalone. Dotfiles owns configuration, plugins and
# verification, but never rewrites the launcher itself.
CODEX_BIN="$HOME/.local/bin/codex"
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"

# Reconcile portable keys and assets; all backups stay in the application home.
provision_codex_config() {
    "$DOTFILES_DIR/bin/ai-config" codex
}

# Install the agent-badge plugin (plugins/agent-badge-codex) from this repo,
# which is also a marketplace (.agents/plugins/marketplace.json). Registered as
# a local directory so it tracks the working tree and needs no network. Never
# fatal: the badge is a convenience.
provision_agent_badge_plugin() {
    [[ "${DOTFILES_AGENT_BADGE_ENABLED:-1}" == "1" ]] || {
        log "Agent-badge disabled; skipping plugin registration."
        return 0
    }
    local codex_cmd="${1:-}"
    [[ -n "$codex_cmd" && -x "$codex_cmd" ]] || codex_cmd="$(command -v codex 2>/dev/null || true)"
    [[ -n "$codex_cmd" ]] || return 0
    [[ -f "$DOTFILES_DIR/.agents/plugins/marketplace.json" ]] || return 0

    if ! "$codex_cmd" plugin marketplace add "$DOTFILES_DIR" >/dev/null 2>&1; then
        warn "Could not register $DOTFILES_DIR as a Codex plugin marketplace."
        return 0
    fi
    if "$codex_cmd" plugin add agent-badge@tafk7 >/dev/null 2>&1; then
        success "Plugin agent-badge installed (tmux window badges for agent sessions)."
        # tmux survives plugin cache replacement. Repair its paths immediately,
        # including when no new agent session has started since the update.
        if [[ -n "${TMUX:-}" ]]; then
            "$DOTFILES_DIR/plugins/shared/agent-badge.tmux" wire >/dev/null 2>&1 || true
        fi
        # Stated on every run: Codex silently skips untrusted hooks, which looks
        # exactly like a broken install.
        log "  Run /hooks inside Codex once to review and trust them."
        log "  Until you do, they are skipped silently and no badges appear."
    else
        warn "Could not install the agent-badge plugin; see plugins/agent-badge-codex/README.md."
    fi
}

run_official_installer() {
    local installer_path="${DOTFILES_CODEX_INSTALLER_SCRIPT:-}"
    local downloaded=false

    # Private test seam: CI supplies a local stand-in so it can exercise
    # ownership behavior without executing a moving upstream installer.
    if [[ -n "$installer_path" ]]; then
        if [[ ! -f "$installer_path" ]]; then
            error "DOTFILES_CODEX_INSTALLER_SCRIPT does not exist: $installer_path"
            return 1
        fi
    else
        if ! command -v curl >/dev/null 2>&1; then
            error "curl is required to install Codex"
            return 1
        fi

        installer_path="$(mktemp)"
        downloaded=true
        if ! download_installer_script "$CODEX_INSTALLER_URL" "$installer_path"; then
            rm -f "$installer_path"
            error "Could not download the official Codex installer"
            return 1
        fi
    fi

    local rc=0
    # The official installer documents CODEX_NON_INTERACTIVE=1 as its prompt
    # suppression control. This prevents the post-install "Start Codex now?"
    # prompt without launching Codex, consuming stdin, or faking a response.
    env PROFILE=/dev/null CODEX_NON_INTERACTIVE=1 sh "$installer_path" || rc=$?
    [[ "$downloaded" == true ]] && rm -f "$installer_path"
    if [[ "$rc" != 0 ]]; then
        error "The official Codex installer failed (exit $rc)"
        return "$rc"
    fi
}

# Config is independent of the binary — provision on every run so it lands even
# when the binary is already present (the early exits below).
provision_codex_config

# Never shadow an externally managed Codex, including under the repository-wide
# --force flag. Replacing another manager's binary must be a separate, explicit
# operation rather than a side effect of refreshing dotfiles.
EXTERNAL_CODEX="$(command -v codex 2>/dev/null || true)"
if [[ -n "$EXTERNAL_CODEX" && "$EXTERNAL_CODEX" != "$CODEX_BIN" ]]; then
    warn "Found an externally-managed codex on PATH: $EXTERNAL_CODEX"
    warn "Skipping install to avoid a shadow copy at $CODEX_BIN."
    provision_agent_badge_plugin "$EXTERNAL_CODEX"
    exit 2
fi

# A symlink at the standard path is owned by the standalone installer. Leave a
# working one alone on normal runs so setup remains fast and offline-friendly.
if [[ "$FORCE" != true && -L "$CODEX_BIN" && -x "$CODEX_BIN" ]] \
    && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex already installed ($("$CODEX_BIN" --version 2>/dev/null | head -n1))."
    provision_agent_badge_plugin "$CODEX_BIN"
    exit 2
fi

# Do not delete an existing launcher first: the official installer performs the
# replacement, so a failed download leaves it intact.
if [[ -x "$CODEX_BIN" ]]; then
    log "Updating or repairing Codex with the official standalone installer..."
else
    log "Installing Codex with the official standalone installer..."
fi

if ! run_official_installer; then
    error "Codex installation failed"
    exit 1
fi

if [[ -x "$CODEX_BIN" ]] && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex installed: $("$CODEX_BIN" --version 2>/dev/null | head -n1)"
    provision_agent_badge_plugin "$CODEX_BIN"
    exit 0
fi

error "Codex installer ran but $CODEX_BIN is not runnable"
exit 1
