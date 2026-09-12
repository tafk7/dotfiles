#!/bin/bash
# Install Google Cloud CLI from Google's signed APT repository.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"; export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
while (( $# )); do
    case "$1" in --force) FORCE=true ;; --dry-run) DRY_RUN=true ;;
        --help|-h) sed -n '2,2p' "$0" | sed 's/^# //'; exit 0 ;;
        *) error "Unknown option: $1"; exit 64 ;; esac
    shift
done
if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would add Google's signed APT repository and install google-cloud-cli"
    exit 0
fi
if [[ "$FORCE" != true ]] && command -v gcloud >/dev/null 2>&1 \
   && dpkg-query -W google-cloud-cli >/dev/null 2>&1; then
    success "Google Cloud CLI already installed"; exit 2
fi
if command -v gcloud >/dev/null 2>&1 && ! dpkg-query -W google-cloud-cli >/dev/null 2>&1; then
    warn "Keeping externally managed Google Cloud CLI: $(command -v gcloud)"
    exit 2
fi
sources_dir="${DOTFILES_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
keyrings_dir="${DOTFILES_GCLOUD_KEYRINGS_DIR:-/usr/share/keyrings}"
main_list="${DOTFILES_APT_MAIN_LIST:-/etc/apt/sources.list}"
if ! grep -Rqs 'https://packages.cloud.google.com/apt' "$sources_dir" "$main_list" 2>/dev/null; then
    tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT INT TERM
    mkdir -m 0700 "$tmpdir/gnupg"
    download_https https://packages.cloud.google.com/apt/doc/apt-key.gpg "$tmpdir/google.asc"
    GNUPGHOME="$tmpdir/gnupg" gpg --batch --show-keys "$tmpdir/google.asc" >/dev/null 2>&1 \
        || { error "Google Cloud repository key is not a valid OpenPGP key"; exit 1; }
    GNUPGHOME="$tmpdir/gnupg" gpg --batch --dearmor --output "$tmpdir/cloud.google.gpg" "$tmpdir/google.asc"
    safe_sudo install -m 0755 -d "$keyrings_dir" "$sources_dir"
    safe_sudo install -m 0644 "$tmpdir/cloud.google.gpg" "$keyrings_dir/cloud.google.gpg"
    printf 'deb [signed-by=%s/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main\n' "$keyrings_dir" \
        | safe_sudo tee "$sources_dir/google-cloud-sdk.list" >/dev/null
    update_packages || exit 1
else
    log "Google Cloud apt repository already configured; reusing existing definition"
fi
if [[ "$FORCE" == true ]] && dpkg-query -W google-cloud-cli >/dev/null 2>&1; then
    safe_sudo apt-get install --reinstall -y google-cloud-cli || exit 1
else
    install_apt gcloud google-cloud-cli || exit 1
fi
command -v gcloud >/dev/null 2>&1 || { error "google-cloud-cli installed but gcloud is unavailable"; exit 1; }
success "Google Cloud CLI installed; authentication remains machine-local"
