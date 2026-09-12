#!/bin/bash
# Install Tailscale without enrolling the machine or changing network policy.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"; export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
while (( $# )); do
    case "$1" in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) sed -n '2,2p' "$0" | sed 's/^# //'; exit 0 ;;
        *) error "Unknown option: $1"; exit 64 ;;
    esac
    shift
done

if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would add Tailscale's signed Ubuntu repository, install tailscale, and enable tailscaled when systemd is running"
    log "[DRY RUN] Would not run tailscale up or consume an auth key"
    exit 0
fi

if [[ "$FORCE" != true ]] && command -v tailscale >/dev/null 2>&1 \
   && dpkg-query -W tailscale >/dev/null 2>&1 \
   && { ! host_systemd_running || systemctl is-active --quiet tailscaled 2>/dev/null; }; then
    success "Tailscale already installed"
    exit 2
fi
codename="$(awk -F= '$1 == "VERSION_CODENAME" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}")"
[[ "$codename" == jammy || "$codename" == noble || "$codename" == resolute ]] \
    || { error "Tailscale support requires Ubuntu 22.04, 24.04, or 26.04 (codename: ${codename:-unknown})"; exit 1; }

sources_dir="${DOTFILES_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
keyrings_dir="${DOTFILES_TAILSCALE_KEYRINGS_DIR:-/usr/share/keyrings}"
main_list="${DOTFILES_APT_MAIN_LIST:-/etc/apt/sources.list}"
existing_source="$(grep -Rsl 'https://pkgs.tailscale.com/stable/ubuntu/' "$sources_dir" "$main_list" 2>/dev/null | head -n1 || true)"
if [[ -n "$existing_source" ]] && ! grep -Eq "(^|/|[[:space:]])${codename}([./[:space:]]|$)" "$existing_source"; then
    error "Existing Tailscale repository does not match Ubuntu codename '$codename': $existing_source"
    exit 1
fi
if [[ -z "$existing_source" ]]; then
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT INT TERM
    mkdir -m 0700 "$tmpdir/gnupg"
    key_url="https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg"
    list_url="https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list"
    download_https "$key_url" "$tmpdir/tailscale.gpg" || exit 1
    download_https "$list_url" "$tmpdir/tailscale.list" || exit 1
    GNUPGHOME="$tmpdir/gnupg" gpg --batch --show-keys "$tmpdir/tailscale.gpg" >/dev/null 2>&1 \
        || { error "Tailscale repository key is not a valid OpenPGP keyring"; exit 1; }
    grep -Fq "https://pkgs.tailscale.com/stable/ubuntu $codename main" "$tmpdir/tailscale.list" \
        || { error "Unexpected Tailscale repository definition"; exit 1; }
    safe_sudo install -m 0755 -d "$keyrings_dir" "$sources_dir"
    safe_sudo install -m 0644 "$tmpdir/tailscale.gpg" "$keyrings_dir/tailscale-archive-keyring.gpg"
    # Normalize the vendor definition to the configured keyring location.
    sed "s|/usr/share/keyrings/tailscale-archive-keyring.gpg|$keyrings_dir/tailscale-archive-keyring.gpg|g" \
        "$tmpdir/tailscale.list" | safe_sudo tee "$sources_dir/tailscale.list" >/dev/null
    update_packages || exit 1
else
    log "Tailscale apt repository already configured; reusing existing definition"
fi

if [[ "$FORCE" == true ]] && dpkg-query -W tailscale >/dev/null 2>&1; then
    safe_sudo apt-get install --reinstall -y tailscale || exit 1
else
    install_apt tailscale tailscale || exit 1
fi
command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1 \
    || { error "tailscale package installed but its client/daemon executables are unavailable"; exit 1; }
if host_systemd_running; then
    safe_sudo systemctl enable --now tailscaled \
        || { error "Tailscale installed but tailscaled could not be enabled/started"; exit 1; }
else
    warn "Tailscale installed; systemd is unavailable, so tailscaled was not enabled"
fi
success "Tailscale installed; enroll manually with 'sudo tailscale up'"
exit 0
