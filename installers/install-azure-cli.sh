#!/bin/bash
# Install Azure CLI and its optional portable Azure DevOps Git integration.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"; export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

while (( $# )); do
    case "$1" in
        --force) FORCE_REINSTALL=true; FORCE_OVERWRITE=true ;;
        --dry-run) DRY_RUN=true ;;
        --help|-h) sed -n '2,2p' "$0" | sed 's/^# //'; exit 0 ;;
        *) error "Unknown option: $1"; exit 64 ;;
    esac
    shift
done

if [[ "${DRY_RUN:-false}" == true ]]; then
    log "[DRY RUN] Would add Microsoft's signed APT repository, install azure-cli, and link git-credential-azdo"
    exit 0
fi

already=false
command -v az >/dev/null 2>&1 && dpkg-query -W azure-cli >/dev/null 2>&1 && already=true
if command -v az >/dev/null 2>&1 && [[ "$already" != true ]]; then
    mkdir -p "$HOME/.local/bin"
    safe_symlink "$DOTFILES_DIR/bin/git-credential-azdo" "$HOME/.local/bin/git-credential-azdo"
    warn "Keeping externally managed Azure CLI: $(command -v az)"
    exit 2
fi
install_azure_cli || exit 1
mkdir -p "$HOME/.local/bin"
safe_symlink "$DOTFILES_DIR/bin/git-credential-azdo" "$HOME/.local/bin/git-credential-azdo"
if command -v az >/dev/null 2>&1; then
    [[ "$already" == true && "${FORCE_REINSTALL:-false}" != true ]] && exit 2
    success "Azure CLI installed; authenticate separately with 'az login'"
    exit 0
fi
error "azure-cli package installed but az is unavailable"
exit 1
