#!/bin/bash
# Install Pi (earendil-works/pi) — a minimal terminal coding agent harness.
#
# Pi self-updates (`pi update`), so this only ensures it is present; --force
# reinstalls. It refuses to shadow an org-managed pi already on PATH.
#
# Not the official installer (pi.dev/install.sh): it appends a PATH line to the
# shell rc files with no opt-out (those are symlinks into this repo), may install
# Node with sudo, and may use npm's global prefix (also sudo). Instead, npm
# installs into a controlled prefix and the binary is linked into ~/.local/bin.
# Pi is a pure-JS npm package, so there is no release binary for eget to pin.
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

# Provision ~/.pi/agent/settings.json with install telemetry off, only when the
# file is absent: it is user-owned (models, keybindings, trust), so an existing
# file only gets a hint. The separate startup version check is controlled by
# PI_SKIP_VERSION_CHECK / PI_OFFLINE (see docs/ai-tools-egress.md).
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

# Node normally comes from the work tier's NVM, but `--pi` can arrive without
# it. That is a requested-install failure, and this does not install Node
# itself: `--pi` must not silently become a partial `--work`.
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

# Don't shadow an externally managed pi: ~/.local/bin comes first on PATH.
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

# Pi 0.85.1 still reaches node-domexception@1.0.0 through its Google auth
# dependency chain. Upstream tracks this known transitive warning; it is not an
# actionable installer failure. Filter only that exact message while preserving
# every other npm warning and error.
filter_pi_npm_stderr() {
    local line
    while IFS= read -r line; do
        case "$line" in
            'npm warn deprecated node-domexception@1.0.0: Use your platform'*) ;;
            *) printf '%s\n' "$line" >&2 ;;
        esac
    done
}

# A private prefix keeps Pi out of NVM's per-version global directory, which
# would vanish on the next Node upgrade; the `env node` shim follows PATH.
# --ignore-scripts is upstream's recommendation; the package has no lifecycle
# scripts.
mkdir -p "$PI_PREFIX"
if ! npm install -g --prefix "$PI_PREFIX" --ignore-scripts "$PI_PACKAGE" \
    2> >(filter_pi_npm_stderr); then
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
