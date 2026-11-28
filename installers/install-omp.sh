#!/bin/bash
# Install Oh My Pi (can1357/oh-my-pi): `omp`, a coding agent forked from Pi.
#
# omp updates itself (`omp update`), so this only ensures it is present;
# --force reinstalls the newest release and --update (setup --upgrade) runs
# omp's own updater. An earlier script launcher stays in front; a separate
# ELF install anywhere on the caller's PATH is preserved.
#
# Not the official installer (omp.sh/install): that pipes a script to sh. The
# release's standalone binary is checked against the release's SHA256SUMS.txt,
# both from the same tag, and placed at ~/.local/bin/omp, where its installer
# puts it too, so `omp update` treats it as its own binary install. Unlike Pi
# it needs no Node: the binary carries its runtime.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component omp; exit; fi

FORCE=false
UPDATE=false
[[ "${1:-}" == "--force" ]] && FORCE=true
[[ "${1:-}" == "--update" ]] && UPDATE=true

OMP_REPO="https://github.com/can1357/oh-my-pi"
OMP_BIN="$HOME/.local/bin/omp"
# Private test seam: a directory holding TAG, SHA256SUMS.txt and the binaries,
# in place of the GitHub release.
OMP_RELEASE_DIR="${DOTFILES_OMP_RELEASE_DIR:-}"

omp_version() { "$1" --version 2>/dev/null | head -n1; }

# Decide before probing our copy or updating it, using the caller's PATH and
# file contents. A launcher need not work before setup; an ELF is external.
EXTERNAL_OMP="$(external_install_path omp "$OMP_BIN")"
if [[ -n "$EXTERNAL_OMP" ]]; then
    warn "Found an externally-managed omp on PATH: $EXTERNAL_OMP"
    warn "Skipping install to avoid a second copy at $OMP_BIN."
    warn "Move/remove the external installation explicitly before installing a dotfiles-owned copy."
    exit 2
fi

# --update: omp's own updater, for the omp installed here.
if [[ "$UPDATE" == true && -x "$OMP_BIN" ]] && omp_version "$OMP_BIN" >/dev/null; then
    before="$(omp_version "$OMP_BIN")"
    "$OMP_BIN" update || { error "omp update failed"; exit 1; }
    after="$(omp_version "$OMP_BIN")"
    [[ "$after" != "$before" ]] || { success "Oh My Pi is current ($after)"; exit 2; }
    success "Oh My Pi updated: $before -> $after"
    exit 0
fi

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && -x "$OMP_BIN" ]] && omp_version "$OMP_BIN" >/dev/null; then
    success "Oh My Pi already installed ($(omp_version "$OMP_BIN")); it updates itself via \`omp update\`."
    exit 2
fi

case "$(uname -m)" in
    x86_64|amd64) asset=omp-linux-x64 ;;
    aarch64|arm64) asset=omp-linux-arm64 ;;
    *) error "Oh My Pi has no Linux release binary for $(uname -m)"; exit 1 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The tag /releases/latest redirects to, so the checksums and the binary come
# from the same release even if a new one is published meanwhile.
if [[ -n "$OMP_RELEASE_DIR" ]]; then
    tag="$(<"$OMP_RELEASE_DIR/TAG")"
else
    command -v curl >/dev/null 2>&1 || { error "curl is required to install Oh My Pi"; exit 1; }
    latest="$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
        --connect-timeout 10 --max-time 60 --head --output /dev/null \
        --write-out '%{url_effective}' "$OMP_REPO/releases/latest")" \
        || { error "Could not find Oh My Pi's latest release"; exit 1; }
    tag="${latest##*/tag/}"
fi
[[ "$tag" =~ ^v[0-9]+(\.[0-9]+)*$ ]] || { error "Unexpected Oh My Pi release tag: ${tag:-none}"; exit 1; }

fetch() {
    if [[ -n "$OMP_RELEASE_DIR" ]]; then
        cp -- "$OMP_RELEASE_DIR/$1" "$work/$1"
    else
        download_https "$OMP_REPO/releases/download/$tag/$1" "$work/$1"
    fi
}

log "Installing Oh My Pi $tag ($asset) into $OMP_BIN..."
fetch SHA256SUMS.txt || { error "Could not download Oh My Pi's SHA256SUMS.txt for $tag"; exit 1; }
expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name { print $1; exit }' "$work/SHA256SUMS.txt")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { error "SHA256SUMS.txt for $tag lists no $asset"; exit 1; }
fetch "$asset" || { error "Could not download $asset for $tag"; exit 1; }
verify_sha256 "$work/$asset" "$expected" || exit 1
chmod 755 "$work/$asset"
"$work/$asset" --version >/dev/null 2>&1 || { error "The downloaded $asset does not run here"; exit 1; }

atomic_replace_binary omp "$work/$asset" "$OMP_BIN" "$tag" || { error "Could not install $OMP_BIN"; exit 1; }

success "Oh My Pi installed: $(omp_version "$OMP_BIN")"
exit 0
