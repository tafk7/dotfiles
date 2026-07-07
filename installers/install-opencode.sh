#!/bin/bash
# Install opencode via the official installer (opencode.ai/install).
#
# opencode self-updates (`opencode upgrade`), so this script only ensures the
# binary is present — it does not pin or manage versions. Re-run with --force to
# reinstall (e.g. to repair a broken binary).
#
# opencode is an "ai" tier tool: installed only by --opencode (or --ai/--full),
# never as a side effect of a tier. Like the other AI installers, it refuses to
# shadow an org-managed opencode already on PATH.
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# The installer honors OPENCODE_INSTALL_DIR above every other location, so pin
# it to ~/.local/bin — the same place claude/codex land and which shell/env.sh
# already puts on PATH. Verify by absolute path: on a fresh machine ~/.local/bin
# is not guaranteed to be on the installer process's PATH.
OPENCODE_BIN="$HOME/.local/bin/opencode"
export OPENCODE_INSTALL_DIR="$HOME/.local/bin"

if [[ "$FORCE" != true && -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" --version >/dev/null 2>&1; then
    success "opencode already installed ($("$OPENCODE_BIN" --version 2>/dev/null | head -n1)); it self-updates."
    exit 2
fi

# Don't shadow an externally-managed opencode. On org-managed machines the CLI
# is provided elsewhere on PATH; installing our own copy at ~/.local/bin/opencode
# would silently override it (shell/env.sh prepends ~/.local/bin). Skip unless
# forced. The shell wrapper resolves whatever `opencode` is on PATH either way.
EXTERNAL_OPENCODE="$(command -v opencode 2>/dev/null || true)"
if [[ "$FORCE" != true && -n "$EXTERNAL_OPENCODE" && "$EXTERNAL_OPENCODE" != "$OPENCODE_BIN" ]]; then
    warn "Found an externally-managed opencode on PATH: $EXTERNAL_OPENCODE"
    warn "Skipping install to avoid a shadow copy at $OPENCODE_BIN."
    warn "Re-run with --force to install the dotfiles-managed copy anyway."
    exit 2
fi

log "Installing opencode via opencode.ai/install (into $OPENCODE_INSTALL_DIR)..."

# ~/.local/bin is already on PATH (shell/env.sh), so the installer should detect
# that and skip editing shell rc files. Those rc files are dotfiles symlinks, so
# if it edits them anyway it writes through into the tracked repo — warn if so.
if ! curl -fsSL https://opencode.ai/install | bash; then
    error "opencode installation failed"
    exit 1
fi

if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "The opencode installer modified a shell rc file that is symlinked into the repo."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted — PATH is already set by shell/env.sh)"
fi

if [[ -x "$OPENCODE_BIN" ]] && "$OPENCODE_BIN" --version >/dev/null 2>&1; then
    success "opencode installed: $("$OPENCODE_BIN" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "opencode installer ran but $OPENCODE_BIN is not runnable"
exit 1
