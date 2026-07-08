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
#
# The installer hardcodes its install dir to ~/.opencode/bin (no env override)
# and, by default, appends a PATH line to a shell rc file. Our rc files are
# dotfiles symlinks, so we pass --no-modify-path to prevent it writing through
# into the tracked repo, then symlink the binary into ~/.local/bin — already on
# PATH via shell/env.sh, and where the registry/verify/uninstall expect it (the
# same approach used for bat/fd).
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

OPENCODE_REAL="$HOME/.opencode/bin/opencode"   # hardcoded install location
OPENCODE_LINK="$HOME/.local/bin/opencode"      # our PATH-visible symlink

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && -x "$OPENCODE_LINK" ]] && "$OPENCODE_LINK" --version >/dev/null 2>&1; then
    success "opencode already installed ($("$OPENCODE_LINK" --version 2>/dev/null | head -n1)); it self-updates."
    exit 2
fi

# Don't shadow an externally-managed opencode. On org-managed machines the CLI
# is provided elsewhere on PATH; installing our own copy would silently override
# it (shell/env.sh prepends ~/.local/bin). Our own symlink and opencode's own
# default install dir are not "external" — anything else is. Skip unless forced.
EXTERNAL_OPENCODE="$(command -v opencode 2>/dev/null || true)"
if [[ "$FORCE" != true && -n "$EXTERNAL_OPENCODE" \
      && "$EXTERNAL_OPENCODE" != "$OPENCODE_LINK" \
      && "$EXTERNAL_OPENCODE" != "$OPENCODE_REAL" ]]; then
    warn "Found an externally-managed opencode on PATH: $EXTERNAL_OPENCODE"
    warn "Skipping install to avoid a shadow copy at $OPENCODE_LINK."
    warn "Re-run with --force to install the dotfiles-managed copy anyway."
    exit 2
fi

log "Installing opencode via opencode.ai/install..."

# --no-modify-path: don't touch shell rc files (we own PATH via shell/env.sh and
# the symlink below). Args are passed to the piped script via `bash -s --`.
if ! curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; then
    error "opencode installation failed"
    exit 1
fi

if [[ ! -x "$OPENCODE_REAL" ]]; then
    error "opencode installer ran but $OPENCODE_REAL is missing"
    exit 1
fi

# Link into ~/.local/bin so it resolves on PATH without an rc edit. opencode
# self-updates in place at $OPENCODE_REAL, so the symlink stays valid.
mkdir -p "$HOME/.local/bin"
ln -sf "$OPENCODE_REAL" "$OPENCODE_LINK"

# Safety net: --no-modify-path should mean no rc edits, but the rc files are
# repo symlinks — warn if anything wrote through anyway.
if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "A shell rc file symlinked into the repo was modified during install."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted)"
fi

if [[ -x "$OPENCODE_LINK" ]] && "$OPENCODE_LINK" --version >/dev/null 2>&1; then
    success "opencode installed: $("$OPENCODE_LINK" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "opencode installed to $OPENCODE_REAL but $OPENCODE_LINK is not runnable"
exit 1
