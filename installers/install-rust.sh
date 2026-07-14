#!/bin/bash
# Install the Rust toolchain via rustup (https://rustup.rs).
#
# rustup self-updates (`rustup update`), so this script only ensures the
# toolchain is present — it does not pin or manage versions. Re-run with --force
# to reinstall (e.g. to repair a broken install).
#
# rust is a "work" tier tool — a userspace language-version manager like nvm,
# needing no sudo. Everything lands in ~/.cargo and ~/.rustup.
#
# rustup-init defaults to appending a `. "$HOME/.cargo/env"` line to shell rc
# files. Our rc files are dotfiles symlinks, so that edit writes straight through
# into the tracked repo — and it's redundant: shell/env.sh already puts
# ~/.cargo/bin on PATH under the guarded single-source-of-truth. We pass
# --no-modify-path to suppress it (the rustup equivalent of nvm's
# PROFILE=/dev/null and opencode's --no-modify-path).
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
RUSTUP_BIN="$CARGO_HOME/bin/rustup"

# Verify by absolute path: on a fresh machine ~/.cargo/bin is not guaranteed to
# be on the installer process's PATH yet.
if [[ "$FORCE" != true && -x "$RUSTUP_BIN" ]] && "$RUSTUP_BIN" --version >/dev/null 2>&1; then
    success "Rust already installed ($("$RUSTUP_BIN" --version 2>/dev/null | head -n1)); it self-updates via 'rustup update'."
    exit 2
fi

log "Installing Rust toolchain via rustup..."

# Download the installer to a file first (inspectable, logged) rather than
# piping the network straight into sh.
rustup_installer="$(mktemp)"
if ! curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs -o "$rustup_installer"; then
    error "Failed to download rustup installer"
    rm -f "$rustup_installer"
    exit 1
fi

log "Running rustup installer from $rustup_installer"
# -y: non-interactive, default profile/toolchain.
# --no-modify-path: don't touch shell rc files (we own PATH via shell/env.sh).
if ! sh "$rustup_installer" -y --no-modify-path; then
    error "rustup installation failed"
    rm -f "$rustup_installer"
    exit 1
fi
rm -f "$rustup_installer"

# Safety net: --no-modify-path should mean no rc edits, but the rc files are
# repo symlinks — warn if anything wrote through anyway.
if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "A shell rc file symlinked into the repo was modified during install."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted)"
fi

# Make cargo/rustc resolvable in this script's own shell for the verify below.
PATH="$CARGO_HOME/bin:$PATH"

if command -v rustc >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
    success "Rust installed: $(rustc --version 2>/dev/null), $(cargo --version 2>/dev/null)"
    exit 0
fi

error "rustup ran but rustc/cargo are not runnable from $CARGO_HOME/bin"
exit 1
