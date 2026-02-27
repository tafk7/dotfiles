#!/bin/bash
# Lazy NVM loader — defers nvm.sh sourcing until first use
# Sourced by both bash.sh and zsh.sh for consistent behavior
#
# nvm.sh adds ~200ms to shell startup. This stub replaces nvm/node/npm
# with thin wrappers that load nvm.sh on first call, then forward the
# invocation.

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    _load_nvm() {
        unset -f _load_nvm nvm node npm npx
        . "$NVM_DIR/nvm.sh"
        [[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"
    }
    nvm()  { _load_nvm; nvm  "$@"; }
    node() { _load_nvm; node "$@"; }
    npm()  { _load_nvm; npm  "$@"; }
    npx()  { _load_nvm; npx  "$@"; }
fi
