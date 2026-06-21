#!/usr/bin/env bash
# Bootstrap dotfiles on a fresh machine.
#
#   curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash -s -- --dev
#   DOTFILES_DIR=~/.dotfiles bash bootstrap.sh --full     # custom clone location
#
# Installs git if missing, clones (or fast-forwards) the repo, then hands off to
# setup.sh. Defaults to the --shell tier when no flag is given.
set -euo pipefail

REPO="${DOTFILES_REPO:-https://github.com/tafk7/dotfiles.git}"
DEST="${DOTFILES_DIR:-$HOME/dev/dotfiles}"

log() { printf '\033[0;34m[bootstrap]\033[0m %s\n' "$*"; }
die() { printf '\033[0;31m[bootstrap] error:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Ensure git is available.
if ! command -v git >/dev/null 2>&1; then
    log "git not found — installing via apt"
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y git
    else
        die "git is missing and apt-get is unavailable; install git manually and re-run"
    fi
fi

# 2. Clone, or fast-forward an existing clone.
if [[ -d "$DEST/.git" ]]; then
    log "updating existing clone at $DEST"
    git -C "$DEST" pull --ff-only || die "pull failed in $DEST (resolve manually, then re-run setup.sh)"
else
    log "cloning $REPO -> $DEST"
    mkdir -p "$(dirname "$DEST")"
    git clone "$REPO" "$DEST"
fi

# 3. Hand off to the tiered installer (default tier: --shell).
cd "$DEST"
log "running ./setup.sh ${*:---shell}"
exec ./setup.sh "${@:---shell}"
