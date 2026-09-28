#!/bin/bash
# Install opencode via the official installer (opencode.ai/install).
#
# opencode self-updates (`opencode upgrade`), so this only ensures it is present;
# --force reinstalls. It refuses to shadow an org-managed opencode on PATH.
#
# The installer always uses ~/.opencode/bin and otherwise appends a PATH line to
# a shell rc file (a symlink into this repo), so pass --no-modify-path and link
# the binary into ~/.local/bin.
#
# Not eget: opencode ships CPU/libc variants (baseline builds for CPUs without
# AVX2, musl). The upstream installer detects the right one; a fixed asset
# filter would SIGILL on older CPUs.
#
# With OPENCODE_ENDPOINT set, this also provisions the hardened config
# (docs/opencode-secure.md).
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

OPENCODE_REAL="$HOME/.opencode/bin/opencode"   # hardcoded install location
OPENCODE_LINK="$HOME/.local/bin/opencode"      # our PATH-visible symlink

# Provision configs/opencode.json only when OPENCODE_ENDPOINT signals a local
# secure endpoint, so personal configs are never touched. An existing config
# needs --force. The file reads its endpoint and model via {env:VAR} at runtime.
provision_opencode_config() {
    local src="$DOTFILES_DIR/configs/opencode.json"
    local dest="$HOME/.config/opencode/opencode.json"

    if [[ -z "${OPENCODE_ENDPOINT:-}" ]]; then
        log "OPENCODE_ENDPOINT unset — skipping opencode config provisioning."
        log "  For a hardened local-endpoint config: set OPENCODE_ENDPOINT (and"
        log "  OPENCODE_MODEL) in ~/.shell.local, then re-run. See docs/opencode-secure.md."
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        warn "configs/opencode.json not found — skipping config provisioning."
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" && "$FORCE" != true ]]; then
        log "opencode config already at $dest — leaving it (use --force to replace)."
        return 0
    fi
    if [[ -e "$dest" ]]; then
        local bak
        bak="$dest.dotfiles-bak-$(date +%Y%m%d-%H%M%S)"
        log "Backing up existing opencode config -> $bak"
        mv "$dest" "$bak"
    fi
    cp "$src" "$dest"
    success "Provisioned hardened opencode config -> $dest"
    log "  (reads OPENCODE_ENDPOINT/OPENCODE_MODEL at runtime; providers locked to 'local')"
}

# Config is independent of the binary install state — provision on every run so
# it lands even when the binary is already present (the early exits below).
provision_opencode_config

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && -x "$OPENCODE_LINK" ]] && "$OPENCODE_LINK" --version >/dev/null 2>&1; then
    success "opencode already installed ($("$OPENCODE_LINK" --version 2>/dev/null | head -n1)); it self-updates."
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
