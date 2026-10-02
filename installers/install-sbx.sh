#!/bin/bash
# Install Docker Sandboxes (sbx) at the pinned version from Docker's signed Ubuntu APT repository.
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

package="${TOOL_APT_PACKAGE[sbx]}"
if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would ensure Docker's signed APT repository, install $package $SBX_VERSION and hold it"
    exit 0
fi

if [[ "$FORCE" != true ]] && command -v sbx >/dev/null 2>&1 \
   && sbx version >/dev/null 2>&1; then
    current="$(sbx version 2>/dev/null | sed -n 's/^sbx version: v\([0-9][0-9.]*\).*/\1/p')"
    if [[ -n "$current" && "$current" != "$SBX_VERSION" ]]; then
        warn "sbx $current is installed; dotfiles pins $SBX_VERSION (rerun with --force to install the pin)"
    fi
    success "sbx already installed"
    exit 2
fi

ensure_docker_repo || exit 1
# The pin may be held already; a deliberate install moves it.
if [[ "$FORCE" == true ]] && dpkg-query -W "$package" >/dev/null 2>&1; then
    safe_apt_get install --reinstall --allow-change-held-packages -y "$package=$SBX_VERSION-*" || exit 1
else
    update_packages || exit 1
    safe_apt_get install --allow-change-held-packages -y "$package=$SBX_VERSION-*" || exit 1
fi
safe_sudo apt-mark hold "$package" >/dev/null || warn "could not hold $package at $SBX_VERSION"
if command -v sbx >/dev/null 2>&1 && sbx version >/dev/null 2>&1; then
    success "Docker Sandboxes installed; KVM readiness and authentication are separate checks"
    exit 0
fi
error "docker-sbx was installed but 'sbx version' failed"
exit 1
