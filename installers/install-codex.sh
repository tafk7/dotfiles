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
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component codex; exit; fi

FORCE=false
# --update (setup --upgrade) runs the official installer as --force does.
[[ "${1:-}" == "--force" || "${1:-}" == "--update" ]] && FORCE=true

# The official standalone installer owns this launcher and the release tree
# under ~/.codex/packages/standalone. Dotfiles owns configuration, plugins and
# verification, but never rewrites the launcher itself.
CODEX_BIN="$HOME/.local/bin/codex"
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"

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

# Never shadow an externally managed Codex, including under the repository-wide
# --force flag. Replacing another manager's binary must be a separate, explicit
# operation rather than a side effect of refreshing dotfiles.
EXTERNAL_CODEX="$(command -v codex 2>/dev/null || true)"
if [[ -n "$EXTERNAL_CODEX" && "$EXTERNAL_CODEX" != "$CODEX_BIN" ]]; then
    warn "Found an externally-managed codex on PATH: $EXTERNAL_CODEX"
    warn "Skipping install to avoid a shadow copy at $CODEX_BIN."
    exit 2
fi

# A symlink at the standard path is owned by the standalone installer. Leave a
# working one alone on normal runs so setup remains fast and offline-friendly.
if [[ "$FORCE" != true && -L "$CODEX_BIN" && -x "$CODEX_BIN" ]] \
    && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex already installed ($("$CODEX_BIN" --version 2>/dev/null | head -n1))."
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
    exit 0
fi

error "Codex installer ran but $CODEX_BIN is not runnable"
exit 1
