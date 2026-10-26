#!/bin/bash
# Install Docker Sandboxes (sbx) at the pinned version from Docker's signed Ubuntu APT repository.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"; export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component sbx; exit; fi

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
installed=""
apt_package_installed "$package" && installed="$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null)"
installed="${installed%%-*}"
held=false
apt_package_held "$package" && held=true

# A hold dotfiles did not place belongs to whoever placed it. One that predates
# receipts cannot be told apart from an administrator's, so it is asked about
# once, and a refusal is remembered.
if [[ "$held" == true ]] && ! hold_owned "$package"; then
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log "[DRY RUN] $package is held at ${installed:-?} by someone other than dotfiles; setup would ask once whether to adopt the hold"
        exit 0
    fi
    if [[ "$(hold_status "$package")" == declined ]]; then
        warn "$package is held at ${installed:-?} by someone other than dotfiles, who moves it; dotfiles pins $SBX_VERSION"
        exit 2
    fi
    if [[ ! -t 0 ]]; then
        warn "$package is held at ${installed:-?} by someone other than dotfiles; rerun setup in a terminal to decide whether dotfiles adopts the hold"
        exit 2
    fi
    answer=""
    read -rp "$package is held at ${installed:-?}, not by dotfiles (or from before dotfiles kept receipts). Let dotfiles manage the hold and move it with the pin ($SBX_VERSION)? [y/N] " answer || true
    if [[ "$answer" != [Yy]* ]]; then
        hold_record "$package" "${installed:--}" declined || exit 1
        log "Leaving the $package hold to its owner; dotfiles will not ask again"
        exit 2
    fi
    hold_record "$package" "${installed:--}" adopted || exit 1
fi

if [[ "${DRY_RUN:-false}" == true ]]; then
    if [[ "$installed" == "$SBX_VERSION" && "$held" == true ]]; then
        log "[DRY RUN] $package $SBX_VERSION is installed and held"
    elif [[ "$installed" == "$SBX_VERSION" ]]; then
        log "[DRY RUN] Would hold $package at $SBX_VERSION"
    else
        log "[DRY RUN] Would ensure Docker's signed APT repository, install $package $SBX_VERSION${installed:+ (replacing $installed)} and hold it"
    fi
    exit 0
fi

# Keep an adoption's receipt status; anything else dotfiles holds, it placed.
receipt=placed
[[ "$(hold_status "$package")" != adopted ]] || receipt=adopted
if [[ "$FORCE" != true && "$installed" == "$SBX_VERSION" ]] && sbx version >/dev/null 2>&1; then
    if [[ "$held" == true ]]; then
        hold_record "$package" "$SBX_VERSION" "$receipt" || exit 1
        success "sbx $SBX_VERSION is installed and held"
        exit 2
    fi
    safe_sudo apt-mark hold "$package" >/dev/null || { error "could not hold $package at $SBX_VERSION"; exit 1; }
    hold_record "$package" "$SBX_VERSION" "$receipt" || exit 1
    success "sbx $SBX_VERSION held"
    exit 0
fi

[[ -z "$installed" ]] || log "sbx $installed installed, moving to $SBX_VERSION..."
ensure_docker_repo || exit 1
if [[ "$FORCE" == true && "$installed" == "$SBX_VERSION" ]]; then
    safe_apt_get install --reinstall --allow-change-held-packages -y "$package=$SBX_VERSION-*" || exit 1
else
    update_packages || exit 1
    safe_apt_get install --allow-change-held-packages -y "$package=$SBX_VERSION-*" || exit 1
fi
safe_sudo apt-mark hold "$package" >/dev/null || { error "could not hold $package at $SBX_VERSION"; exit 1; }
hold_record "$package" "$SBX_VERSION" "$receipt" || exit 1
if command -v sbx >/dev/null 2>&1 && sbx version >/dev/null 2>&1; then
    success "Docker Sandboxes $SBX_VERSION installed and held; KVM readiness and authentication are separate checks"
    exit 0
fi
error "docker-sbx was installed but 'sbx version' failed"
exit 1
