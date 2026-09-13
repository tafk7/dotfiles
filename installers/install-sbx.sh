#!/bin/bash
# Install Docker Sandboxes (sbx) from Docker's signed Ubuntu APT repository.
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
    log "[DRY RUN] Would ensure Docker's signed APT repository and install docker-sbx"
    exit 0
fi

if [[ "$FORCE" != true ]] && command -v sbx >/dev/null 2>&1 \
   && sbx version >/dev/null 2>&1; then
    success "sbx already installed"
    exit 2
fi

ensure_docker_repo || exit 1
if [[ "$FORCE" == true ]] && dpkg-query -W "${TOOL_APT_PACKAGE[sbx]}" >/dev/null 2>&1; then
    safe_apt_get install --reinstall -y "${TOOL_APT_PACKAGE[sbx]}" || exit 1
else
    install_apt sbx "${TOOL_APT_PACKAGE[sbx]}" || exit 1
fi
if command -v sbx >/dev/null 2>&1 && sbx version >/dev/null 2>&1; then
    success "Docker Sandboxes installed; KVM readiness and authentication are separate checks"
    exit 0
fi
error "docker-sbx was installed but 'sbx version' failed"
exit 1
