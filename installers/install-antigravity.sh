#!/bin/bash
# Install Google Antigravity's terminal CLI, `agy` (issues/antigravity-cli.md).
#
# Not the official installer (antigravity.google/cli/install.sh): that ends in
# `agy install`, which edits the shell profile (a symlink into this repo).
# Instead this reads the same per-platform release manifest (version, url,
# sha512), downloads the tarball, checks its SHA-512, and installs its one
# member, `antigravity`, as ~/.local/bin/agy. It never runs `agy install` or
# `agy update`. --update (setup --upgrade, dotfiles upgrade antigravity) is the
# same fetch when the manifest names another version; shell/env.sh turns the
# CLI's own update check off. An earlier readable shebang script declaring
# '# dotfiles-launcher: agy' in its first ten lines stays in front. Creating
# or forcibly reinstalling a copy refuses separate installs, including
# unmarked scripts and ELF binaries. A working managed copy keeps updating
# by absolute path even with a separate install earlier on PATH.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
# Also covers the common artifact helpers' version probes after replacement.
export AGY_CLI_DISABLE_AUTO_UPDATE=true
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component antigravity; exit; fi

FORCE=false
UPDATE=false
[[ "${1:-}" == "--force" ]] && FORCE=true
[[ "${1:-}" == "--update" ]] && UPDATE=true

AGY_BIN="$HOME/.local/bin/agy"
AGY_MANIFEST_BASE="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"

# --version contacts nothing; the variable makes sure no update check runs.
agy_version() { AGY_CLI_DISABLE_AUTO_UPDATE=true "$1" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1; }

installed=""
[[ -x "$AGY_BIN" ]] && installed="$(agy_version "$AGY_BIN" || true)"

# Verify by absolute path: on a fresh machine ~/.local/bin is not guaranteed to
# be on the installer process's PATH.
if [[ "$FORCE" != true && "$UPDATE" != true && -n "$installed" ]]; then
    success "Antigravity CLI already installed ($installed); dotfiles upgrade antigravity updates it."
    exit 2
fi

# Retaining/updating a working managed copy creates no second copy. Inspect
# PATH only when creating or forcibly replacing it, as the omp installer does.
if [[ -z "$installed" || "$FORCE" == true ]]; then
    EXTERNAL_AGY="$(external_install_path agy "$AGY_BIN")"
    if [[ -n "$EXTERNAL_AGY" ]]; then
        warn_external_install agy "$EXTERNAL_AGY" "$AGY_BIN"
        exit 2
    fi
fi

case "$(uname -m)" in
    x86_64|amd64) platform=linux_amd64 ;;
    aarch64|arm64) platform=linux_arm64 ;;
    *) error "The Antigravity CLI has no Linux release for $(uname -m)"; exit 1 ;;
esac
# Private test seam, also a way to install from a mirror: the manifest's URL,
# https:// or (with a file:// tarball URL in it) file://.
manifest_url="${DOTFILES_ANTIGRAVITY_MANIFEST_URL:-$AGY_MANIFEST_BASE/$platform.json}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# fetch URL DEST: https through download_https; file:// only from a file://
# manifest.
fetch() {
    case "$1" in
        https://*) download_https "$1" "$2" ;;
        file://*)
            [[ "$manifest_url" == file://* ]] || { error "Refusing a local file from a remote manifest: $1"; return 1; }
            cp -- "${1#file://}" "$2"
            ;;
        *) error "Refusing to download from: $1"; return 1 ;;
    esac
}

fetch "$manifest_url" "$work/manifest.json" || { error "Could not read the Antigravity CLI release manifest"; exit 1; }
IFS=$'\t' read -r version url sha512 < <(python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))
print("\t".join(str(m.get(k, "")) for k in ("version", "url", "sha512")))
' "$work/manifest.json" 2>/dev/null) || { error "The Antigravity CLI release manifest is not JSON"; exit 1; }
[[ "$version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || { error "Unexpected version in the release manifest: ${version:-none}"; exit 1; }
[[ "$sha512" =~ ^[0-9a-f]{128}$ ]] || { error "The release manifest has no SHA-512"; exit 1; }

if [[ "$UPDATE" == true && "$FORCE" != true && "$installed" == "$version" ]]; then
    success "Antigravity CLI is current ($installed)"
    exit 2
fi

log "Installing Antigravity CLI $version into $AGY_BIN..."
fetch "$url" "$work/cli.tar.gz" || { error "Could not download the Antigravity CLI $version"; exit 1; }
verify_sha512 "$work/cli.tar.gz" "$sha512" || exit 1
validate_tar_archive "$work/cli.tar.gz" || exit 1
mkdir "$work/x"
tar -xzf "$work/cli.tar.gz" -C "$work/x" antigravity 2>/dev/null \
    || { error "The Antigravity CLI archive holds no antigravity binary"; exit 1; }
staged="$work/x/antigravity"
[[ -f "$staged" && ! -L "$staged" ]] || { error "The archive's antigravity is not a regular file"; exit 1; }
chmod 755 "$staged"
[[ "$(agy_version "$staged" || true)" == "$version" ]] \
    || { error "The downloaded binary does not run here or is not $version"; exit 1; }

atomic_replace_binary antigravity "$staged" "$AGY_BIN" "$version" || { error "Could not install $AGY_BIN"; exit 1; }

if [[ -n "$installed" ]]; then
    success "Antigravity CLI updated: $installed -> $version"
else
    success "Antigravity CLI installed: $version"
fi
exit 0
