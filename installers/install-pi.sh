#!/bin/bash
# Install Pi (earendil-works/pi) — a minimal terminal coding agent harness.
#
# Pi self-updates (`pi update`), so this script only ensures the binary is
# present — it does not pin or manage versions. Re-run with --force to reinstall
# (e.g. to repair a broken install).
#
# Pi is an "ai" tier tool: installed only by --pi (or --ai/--full), never as a
# side effect of a tier. Like the other AI installers, it refuses to shadow an
# org-managed pi already on PATH.
#
# WHY NOT THE OFFICIAL INSTALLER (https://pi.dev/install.sh):
# It interactively prompts to append a PATH line to .bashrc/.zshrc/.profile and
# offers NO --no-modify-path escape (opencode's installer does). Our rc files are
# dotfiles symlinks, so that write-through would dirty the tracked repo. It will
# also auto-install Node via apt/brew (sudo) when missing, and can install into
# npm's global prefix (/usr/local/lib/node_modules — also sudo). We want none of
# that, so we drive npm ourselves into a controlled prefix and symlink the binary
# into ~/.local/bin — already on PATH via shell/env.sh, and where the
# registry/verify/uninstall expect it (the same approach used for opencode).
#
# WHY npm AND NOT eget: Pi is a pure-JS npm package (@earendil-works/pi-coding-
# agent, bin "pi" -> dist/bundle/cli.js), not a compiled release artifact. There
# are no GitHub binary assets to pin. Correspondingly there is no CPU/libc
# variant detection to replicate, unlike opencode.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

PI_PACKAGE="@earendil-works/pi-coding-agent"
PI_NODE_MIN="22.19.0"                       # package.json engines.node
PI_PREFIX="$HOME/.pi/agent/install"         # matches upstream's managed-mode dir
PI_REAL="$PI_PREFIX/bin/pi"
PI_LINK="$HOME/.local/bin/pi"               # our PATH-visible symlink

# Provision ~/.pi/agent/settings.json with the install/update telemetry ping to
# pi.dev/api/report-install turned off.
#
# ONLY when absent. settings.json is a rich, user-owned file (models,
# keybindings, project trust, compaction), so we never overwrite it; for an
# existing file we point at the key to add. Same policy as
# provision_claude_settings in installers/install-claude.sh.
#
# Note this does NOT disable the separate startup version check against
# pi.dev/api/latest-version — set PI_SKIP_VERSION_CHECK=1, or PI_OFFLINE=1 to
# disable all startup network activity. See docs/ai-tools-egress.md.
provision_pi_settings() {
    local src="$DOTFILES_DIR/configs/pi-settings.json"
    local dest="$HOME/.pi/agent/settings.json"
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dest")"

    if [[ -e "$dest" ]]; then
        log "Existing $dest left untouched."
        log "  To disable install/update telemetry, add \"enableInstallTelemetry\": false"
        log "  (see configs/pi-settings.json and docs/ai-tools-egress.md)."
        return 0
    fi
    cp "$src" "$dest"
    success "Provisioned ~/.pi/agent/settings.json (install/update telemetry off)."
}

# Compare dotted versions without bc/sort -V dependence on field count.
# Returns 0 when $1 >= $2.
version_ge() {
    local have="$1" want="$2"
    [[ "$(printf '%s\n%s\n' "$want" "$have" | sort -V | head -n1)" == "$want" ]]
}

# Node gate. Pi is the only npm-based tool in the registry; every other AI CLI
# is a standalone binary. Node comes from the work tier's NVM, but Pi sits in the
# ai tier, so `--pi` on a fresh machine can legitimately arrive without it.
#
# This is a requested-install failure: setup must exit nonzero rather than call
# a missing prerequisite "up to date". Deliberately does NOT
# install Node itself: `--pi` must not silently become a partial `--work`.
require_node() {
    local have
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        warn "Pi needs Node >= $PI_NODE_MIN and npm; neither was found on PATH."
        warn "Install a Node toolchain first, then re-run:"
        warn "    ./setup.sh --work     # installs NVM"
        warn "    ./setup.sh --pi"
        exit 1
    fi
    have="$(node --version 2>/dev/null | sed 's/^v//')"
    if [[ -z "$have" ]] || ! version_ge "$have" "$PI_NODE_MIN"; then
        warn "Pi needs Node >= $PI_NODE_MIN; found ${have:-unknown}."
        warn "Upgrade Node, then re-run: ./setup.sh --pi"
        warn "    (with NVM: nvm install --lts && nvm alias default node)"
        exit 1
    fi
}

# Config is independent of the binary install state — provision on every run so
# it lands even when the binary is already present (the early exits below).
provision_pi_settings

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && -x "$PI_LINK" ]] && "$PI_LINK" --version >/dev/null 2>&1; then
    success "Pi already installed ($("$PI_LINK" --version 2>/dev/null | head -n1)); it self-updates via \`pi update\`."
    exit 2
fi

# Pi already present at our prefix but not linked (a prior install, or a broken
# symlink) — adopt it by (re)creating the symlink, no re-download needed.
if [[ "$FORCE" != true && -x "$PI_REAL" ]] && "$PI_REAL" --version >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$PI_REAL" "$PI_LINK"
    success "Pi already installed at $PI_REAL; linked into ~/.local/bin."
    exit 0
fi

# Don't shadow an externally-managed pi. On org-managed machines the CLI may be
# provided elsewhere on PATH; installing our own copy would silently override it
# (shell/env.sh prepends ~/.local/bin). Our own symlink and our prefix are not
# "external" — anything else is always preserved.
EXTERNAL_PI="$(command -v pi 2>/dev/null || true)"
if [[ -n "$EXTERNAL_PI" \
      && "$EXTERNAL_PI" != "$PI_LINK" \
      && "$EXTERNAL_PI" != "$PI_REAL" ]]; then
    warn "Found an externally-managed pi on PATH: $EXTERNAL_PI"
    warn "Skipping install to avoid a shadow copy at $PI_LINK."
    warn "Move/remove the external installation explicitly before installing a dotfiles-owned copy."
    exit 2
fi

require_node

log "Installing Pi ($PI_PACKAGE) into $PI_PREFIX..."

# -g --prefix: put the package under $PI_PREFIX/lib and its bin shim in
# $PI_PREFIX/bin, isolated from whichever Node version NVM currently defaults to
# (a plain `npm install -g` would land in ~/.nvm/versions/node/<ver>/bin and
# vanish on the next Node upgrade). The bin shim is `#!/usr/bin/env node`, so it
# follows PATH and keeps working across Node versions.
#
# --ignore-scripts is upstream's own documented recommendation and costs nothing
# here: the package declares no install/postinstall lifecycle scripts.
mkdir -p "$PI_PREFIX"
if ! npm install -g --prefix "$PI_PREFIX" --ignore-scripts "$PI_PACKAGE"; then
    error "Pi installation failed (npm install $PI_PACKAGE)"
    exit 1
fi

if [[ ! -x "$PI_REAL" ]]; then
    error "npm reported success but $PI_REAL is missing"
    exit 1
fi

# Link into ~/.local/bin so it resolves on PATH without an rc edit.
mkdir -p "$HOME/.local/bin"
ln -sf "$PI_REAL" "$PI_LINK"

# Safety net: we never invoke the upstream installer, so nothing should have
# touched the rc files — but they are repo symlinks, so warn if anything did.
if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "A shell rc file symlinked into the repo was modified during install."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted)"
fi

if [[ -x "$PI_LINK" ]] && "$PI_LINK" --version >/dev/null 2>&1; then
    success "Pi installed: $("$PI_LINK" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "Pi installed to $PI_REAL but $PI_LINK is not runnable"
exit 1
