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
#
# WHY THE OFFICIAL SCRIPT, NOT eget: opencode ships CPU/libc VARIANT builds
# (opencode-linux-x64, -x64-baseline for CPUs without AVX2, -musl for Alpine).
# The upstream installer probes /proc/cpuinfo + ldd and picks the right one. A
# fixed eget asset filter would always grab the AVX2 glibc build and SIGILL on
# an older work VM (or fail on musl). Do NOT "pin it with eget" without
# replicating that detection.
#
# This script also provisions a hardened, env-driven ~/.config/opencode config
# (local-endpoint only, share disabled, OTEL local) when OPENCODE_ENDPOINT is
# set — see configs/opencode.json and docs/opencode-secure.md.
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

OPENCODE_REAL="$HOME/.opencode/bin/opencode"   # hardcoded install location
OPENCODE_LINK="$HOME/.local/bin/opencode"      # our PATH-visible symlink

# Provision the hardened, env-driven config (configs/opencode.json) into
# ~/.config/opencode. Gated on OPENCODE_ENDPOINT so we never touch a personal
# machine's opencode config — setting that env var is the "I have a local secure
# endpoint" signal. Idempotent: won't clobber an existing config without --force.
# The config uses opencode's {env:VAR} substitution, so it reads OPENCODE_ENDPOINT
# / OPENCODE_MODEL live at runtime — no re-provisioning needed when they change.
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
