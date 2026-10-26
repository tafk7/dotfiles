#!/bin/bash
# Install the Node.js release versions.lock pins, with the npm it bundles,
# through NVM, and make it NVM's default. Other installed releases and project
# versions (.nvmrc) are left alone. --force adopts Node under an NVM dotfiles
# does not own; it does not reinstall a release.

set -eo pipefail  # NVM uses unbound variables internally

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"
# Observation reports what is installed and changes nothing, so it branches
# before any provisioning below (lib/observe.sh).
if [[ "${1:-}" == --observe ]]; then observe_component node; exit; fi

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] || { error "NVM is not installed at $NVM_DIR (install-nvm.sh installs it)"; exit 1; }

NODE_VERSION="$(versions_field node want)" || { error "versions.lock has no node row for $(get_arch)"; exit 1; }
NODE_VERSION="${NODE_VERSION#v}"
NODE_IDENTITY="$(versions_field node identity)"
NPM_VERSION="$(versions_field npm want any)" || { error "versions.lock has no npm row"; exit 1; }
node_dir="$NVM_DIR/versions/node/v$NODE_VERSION"

# Releases under an NVM someone else installed are theirs.
nvm_owner=""
IFS=$'\t' read -r _ _ nvm_owner _ < <(ledger_line nvm 2>/dev/null || true) || true
if [[ "$FORCE" != true && "$nvm_owner" != dotfiles ]]; then
    log "Preserving Node under an NVM dotfiles does not own; --force adopts it"
    exit 2
fi

node_identity() { [[ -x "$node_dir/bin/node" ]] && printf 'sha256:%s\n' "$(sha256sum "$node_dir/bin/node" | awk '{print $1}')"; }
npm_version() {
    sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$node_dir/lib/node_modules/npm/package.json" 2>/dev/null | head -n1
}
default_is_pin() {
    [[ "$(head -n1 "$NVM_DIR/alias/default" 2>/dev/null)" == "$NODE_VERSION" \
       && "$(readlink -f "$NVM_DIR/default" 2>/dev/null)" == "$node_dir" ]]
}

if [[ "$(node_identity)" == "$NODE_IDENTITY" && "$(npm_version)" == "$NPM_VERSION" ]] && default_is_pin; then
    success "Node v$NODE_VERSION (npm $NPM_VERSION) is NVM's default"
    exit 2
fi

# Keep a Windows npm on PATH from shadowing NVM's.
if [[ -n "${PATH:-}" ]]; then
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/mnt/c/' | tr '\n' ':' | sed 's/:$//')
    export PATH
fi
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh" --no-use

if [[ ! -x "$node_dir/bin/node" ]]; then
    # NVM checks the download against nodejs.org's SHASUMS256.txt; the binary
    # is then checked against the lock below.
    log "Installing Node v$NODE_VERSION through NVM..."
    nvm install "$NODE_VERSION" || { error "nvm install $NODE_VERSION failed"; exit 1; }
fi
actual="$(node_identity || true)"
if [[ "$actual" != "$NODE_IDENTITY" ]]; then
    error "Node v$NODE_VERSION at $node_dir is not the locked build (${actual:-missing}); remove it with 'nvm uninstall $NODE_VERSION' and rerun"
    exit 1
fi

# npm is the version this release bundles; an independently upgraded npm is
# moved back to it.
if [[ "$(npm_version)" != "$NPM_VERSION" ]]; then
    log "Restoring npm $NPM_VERSION, bundled with Node v$NODE_VERSION (found $(npm_version))..."
    PATH="$node_dir/bin:$PATH" npm install -g --no-fund --no-audit "npm@$NPM_VERSION" >/dev/null \
        || { error "npm install -g npm@$NPM_VERSION failed"; exit 1; }
    [[ "$(npm_version)" == "$NPM_VERSION" ]] || { error "npm is $(npm_version) after restoring $NPM_VERSION"; exit 1; }
fi

previous="$(node_default_dir 2>/dev/null || true)"
nvm alias default "$NODE_VERSION" >/dev/null || { error "nvm alias default $NODE_VERSION failed"; exit 1; }
# A stable symlink lets shell/env.sh put Node on PATH without sourcing nvm.sh,
# which non-interactive shells never do.
ln -sfn "$node_dir" "$NVM_DIR/default" || exit 1
if [[ -n "$previous" && "$previous" != "$node_dir" ]]; then
    globals="$(find "$previous/lib/node_modules" -mindepth 1 -maxdepth 1 ! -name npm ! -name corepack -printf '%f ' 2>/dev/null || true)"
    [[ -z "$globals" ]] || warn "Global packages stay with ${previous##*/}: ${globals% } ('nvm reinstall-packages ${previous##*/}' copies them)"
fi
success "Node v$NODE_VERSION (npm $NPM_VERSION) is NVM's default"
