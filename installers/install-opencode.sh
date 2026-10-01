#!/bin/bash
# Install opencode via the official installer (opencode.ai/install).
#
# A rerun only ensures it is present; --force (bin/ai-update opencode) reruns
# the installer, which fetches the latest release. It refuses to shadow an
# org-managed opencode on PATH.
#
# The installer always uses ~/.opencode/bin and otherwise appends a PATH line to
# a shell rc file (a symlink into this repo), so pass --no-modify-path and link
# the binary into ~/.local/bin.
#
# Not eget: opencode ships CPU/libc variants (baseline builds for CPUs without
# AVX2, musl). The upstream installer detects the right one; a fixed asset
# filter would SIGILL on older CPUs.
#
# Portable preferences are reconciled by bin/ai-config: update notices instead
# of silent self-updates, because opencode's updater omits --no-modify-path.
# Providers belong to whatever configures them.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

OPENCODE_REAL="$HOME/.opencode/bin/opencode"   # hardcoded install location
OPENCODE_LINK="$HOME/.local/bin/opencode"      # our PATH-visible symlink

# Configuration is independent of the binary install state: reconcile it on
# every run so it lands even when the binary is already present (the early
# exits below).
"$DOTFILES_DIR/bin/ai-config" opencode

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && -x "$OPENCODE_LINK" ]] && "$OPENCODE_LINK" --version >/dev/null 2>&1; then
    success "opencode already installed ($("$OPENCODE_LINK" --version 2>/dev/null | head -n1)); update with bin/ai-update opencode."
    exit 2
fi

# opencode already present at its real location but not yet linked (a prior
# install, or the installer's own default PATH setup) — just adopt it by
# (re)creating our symlink, no re-download needed.
if [[ "$FORCE" != true && -x "$OPENCODE_REAL" ]] && "$OPENCODE_REAL" --version >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$OPENCODE_REAL" "$OPENCODE_LINK"
    success "opencode already installed at $OPENCODE_REAL; linked into ~/.local/bin."
    exit 0
fi

# Don't shadow an externally managed opencode: ~/.local/bin comes first on PATH.
EXTERNAL_OPENCODE="$(command -v opencode 2>/dev/null || true)"
if [[ -n "$EXTERNAL_OPENCODE" \
      && "$EXTERNAL_OPENCODE" != "$OPENCODE_LINK" \
      && "$EXTERNAL_OPENCODE" != "$OPENCODE_REAL" ]]; then
    warn "Found an externally-managed opencode on PATH: $EXTERNAL_OPENCODE"
    warn "Skipping install to avoid a shadow copy at $OPENCODE_LINK."
    warn "Move/remove the external installation explicitly before installing a dotfiles-owned copy."
    exit 2
fi

log "Installing opencode via opencode.ai/install..."

# --no-modify-path: don't touch shell rc files (we own PATH via shell/env.sh and
# the symlink below). Args are passed to the piped script via `bash -s --`.
opencode_installer="${DOTFILES_OPENCODE_INSTALLER_SCRIPT:-}"
downloaded_installer=false
if [[ -z "$opencode_installer" ]]; then
    opencode_installer="$(mktemp)"
    downloaded_installer=true
    download_installer_script https://opencode.ai/install "$opencode_installer" || exit 1
elif [[ ! -s "$opencode_installer" ]]; then
    error "DOTFILES_OPENCODE_INSTALLER_SCRIPT is missing or empty: $opencode_installer"
    exit 1
fi
rc_before="$(rc_snapshot)"
if ! bash "$opencode_installer" --no-modify-path; then
    [[ "$downloaded_installer" == true ]] && rm -f "$opencode_installer"
    error "opencode installation failed"
    exit 1
fi
[[ "$downloaded_installer" == true ]] && rm -f "$opencode_installer"

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
warn_if_rc_changed "$rc_before"

if [[ -x "$OPENCODE_LINK" ]] && "$OPENCODE_LINK" --version >/dev/null 2>&1; then
    success "opencode installed: $("$OPENCODE_LINK" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "opencode installed to $OPENCODE_REAL but $OPENCODE_LINK is not runnable"
exit 1
