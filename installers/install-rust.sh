#!/bin/bash
# Install rustup (https://rustup.rs) with the Rust toolchain versions.lock pins
# as its default.
#
# rustup itself self-updates; the default toolchain moves only with the pin.
# Other toolchains, and a project's own (rust-toolchain.toml), are kept. A
# rustup dotfiles did not install keeps its default unless --force adopts it.
# No sudo: everything lands in ~/.cargo and ~/.rustup. --no-modify-path stops
# rustup-init editing the shell rc files (symlinks into this repo);
# shell/env.sh already puts ~/.cargo/bin on PATH.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component rust; exit; fi

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
RUSTUP_BIN="$CARGO_HOME/bin/rustup"
TOOLCHAIN="$(versions_field rust want any)" || { error "versions.lock has no rust row"; exit 1; }

# rustup runs from / with RUSTUP_TOOLCHAIN unset and auto-install off, so no
# project override answers and only an explicit install installs.
rustup_neutral() { (cd / && env -u RUSTUP_TOOLCHAIN RUSTUP_AUTO_INSTALL=0 "$RUSTUP_BIN" "$@"); }
default_toolchain() {
    rustup_neutral default 2>/dev/null | awk 'NR == 1 { print $1 }' \
        | sed -E 's/-(x86_64|aarch64)-unknown-linux-(gnu|musl)$//'
}

# Verify by absolute path: on a fresh machine ~/.cargo/bin is not guaranteed to
# be on the installer process's PATH yet.
if [[ -x "$RUSTUP_BIN" ]] && rustup_neutral --version >/dev/null 2>&1; then
    owner=""
    IFS=$'\t' read -r _ _ owner _ < <(ledger_line rust 2>/dev/null || true) || true
    if [[ "$FORCE" != true && "$owner" != dotfiles ]]; then
        log "Preserving the toolchains of a rustup dotfiles does not own; --force adopts it"
        exit 2
    fi
    current="$(default_toolchain)"
    if [[ "$current" == "$TOOLCHAIN" ]]; then
        success "Rust $TOOLCHAIN is rustup's default"
        exit 2
    fi
    log "Moving rustup's default toolchain from ${current:-none} to $TOOLCHAIN..."
    rustup_neutral toolchain install "$TOOLCHAIN" --no-self-update \
        || { error "rustup toolchain install $TOOLCHAIN failed"; exit 1; }
    rustup_neutral default "$TOOLCHAIN" || { error "rustup default $TOOLCHAIN failed"; exit 1; }
    [[ "$(default_toolchain)" == "$TOOLCHAIN" ]] || { error "rustup's default is not $TOOLCHAIN after switching"; exit 1; }
    success "Rust $TOOLCHAIN is rustup's default; other toolchains are kept"
    exit 0
fi

log "Installing Rust toolchain via rustup..."

# Download to a file rather than piping the network into sh.
rustup_installer="${DOTFILES_RUSTUP_INSTALLER_SCRIPT:-}"
downloaded_installer=false
if [[ -z "$rustup_installer" ]]; then
    rustup_installer="$(mktemp)"
    downloaded_installer=true
fi
if [[ "$downloaded_installer" == true ]] && ! download_installer_script https://sh.rustup.rs "$rustup_installer"; then
    error "Failed to download rustup installer"
    rm -f "$rustup_installer"
    exit 1
fi
[[ -s "$rustup_installer" ]] || { error "Rust installer is missing or empty: $rustup_installer"; exit 1; }

log "Running rustup installer from $rustup_installer"
rc_before="$(rc_snapshot)"
if ! sh "$rustup_installer" -y --no-modify-path --default-toolchain "$TOOLCHAIN"; then
    error "rustup installation failed"
    [[ "$downloaded_installer" == true ]] && rm -f "$rustup_installer"
    exit 1
fi
[[ "$downloaded_installer" == true ]] && rm -f "$rustup_installer"

# Safety net: --no-modify-path should mean no rc edits, but the rc files are
# repo symlinks — warn if anything wrote through anyway.
warn_if_rc_changed "$rc_before"

# Make cargo/rustc resolvable in this script's own shell for the verify below.
PATH="$CARGO_HOME/bin:$PATH"

if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1 && [[ "$(default_toolchain)" == "$TOOLCHAIN" ]]; then
    success "Rust $TOOLCHAIN installed: $(cd / && rustc --version 2>/dev/null), $(cd / && cargo --version 2>/dev/null)"
    exit 0
fi

error "rustup ran but rustc/cargo are not runnable from $CARGO_HOME/bin, or its default is not $TOOLCHAIN"
exit 1
