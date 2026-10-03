#!/bin/bash
# Install the stable OpenCode V2 CLI without modifying shell startup files.
# Existing V2 installs are reconciled; --force updates. Owned V1 installs migrate.
set -euo pipefail
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
FORCE=false
[[ "${1:-}" == --force ]] && FORCE=true
OPENCODE_REAL="$HOME/.opencode/bin/opencode"
OPENCODE_LINK="$HOME/.local/bin/opencode"

v2_version() {
    local version
    version="$("$1" --version 2>/dev/null)" || return 1
    [[ "$version" =~ ^(opencode[[:space:]]+)?v?2\.[0-9]+\.[0-9]+$ ]]
}

# Check ownership before configuration or symlink changes, including --force.
external="$(command -v opencode 2>/dev/null || true)"
if [[ -n "$external" && "$external" != "$OPENCODE_REAL" && "$external" != "$OPENCODE_LINK" ]] ||
   [[ -e "$OPENCODE_LINK" && "$(readlink -f "$OPENCODE_LINK")" != "$OPENCODE_REAL" ]]; then
    warn "Externally managed opencode found; use its package manager to migrate to V2."
    exit 2
fi
if [[ "$FORCE" != true ]] && v2_version "$OPENCODE_REAL"; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$OPENCODE_REAL" "$OPENCODE_LINK"
    "$DOTFILES_DIR/bin/ai-config" opencode
    success "OpenCode V2 already installed; update with bin/ai-update opencode."
    exit 2
fi

installer="${DOTFILES_OPENCODE_INSTALLER_SCRIPT:-}"
downloaded=false
backup_dir=""
cleanup() {
    [[ "$downloaded" != true ]] || rm -f -- "$installer"
    return 0
}
trap cleanup EXIT
if [[ -z "$installer" ]]; then
    installer="$(mktemp)"
    downloaded=true
    download_installer_script https://opencode.ai/v2/install "$installer" || exit 1
elif [[ ! -s "$installer" ]]; then
    error "DOTFILES_OPENCODE_INSTALLER_SCRIPT is missing or empty: $installer"
    exit 1
fi
args=(--no-modify-path)
if [[ -n "${DOTFILES_OPENCODE_VERSION:-}" ]]; then
    [[ "$DOTFILES_OPENCODE_VERSION" =~ ^2\.[0-9]+\.[0-9]+$ ]] || { error "Expected a stable V2 version"; exit 1; }
    args+=(--version "$DOTFILES_OPENCODE_VERSION")
fi
if [[ -f "$OPENCODE_REAL" ]]; then
    backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencode-binary-backup.XXXXXX")"
    cp -p "$OPENCODE_REAL" "$backup_dir/opencode"
    # A shared V2 service must stop before its executable is replaced.
    if v2_version "$OPENCODE_REAL"; then "$OPENCODE_REAL" service stop; fi
fi
rc_before="$(rc_snapshot)"
log "Installing stable OpenCode V2 via opencode.ai/v2/install..."
if ! VERSION='' bash "$installer" "${args[@]}" || ! v2_version "$OPENCODE_REAL"; then
    if [[ -n "$backup_dir" ]]; then
        cp -p "$backup_dir/opencode" "$OPENCODE_REAL.restore"
        mv -f "$OPENCODE_REAL.restore" "$OPENCODE_REAL"
        warn "Restored the previous binary; backup retained at $backup_dir"
    else
        [[ ! -f "$OPENCODE_REAL" ]] || mv "$OPENCODE_REAL" "$OPENCODE_REAL.failed"
    fi
    warn_if_rc_changed "$rc_before"
    error "OpenCode V2 installation/verification failed; configuration was not migrated"
    exit 1
fi
mkdir -p "$HOME/.local/bin"
ln -sfn "$OPENCODE_REAL" "$OPENCODE_LINK"
warn_if_rc_changed "$rc_before"
# Native preferences only after a verified V2 binary is available.
"$DOTFILES_DIR/bin/ai-config" opencode
[[ -z "$backup_dir" ]] || log "Previous binary retained at $backup_dir"
success "Installed $("$OPENCODE_REAL" --version)"
