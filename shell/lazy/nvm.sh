#!/bin/bash
# Lazy NVM loader: nvm.sh is slow to source, so nvm/node/npm are thin wrappers
# that load it on first call and then forward the invocation.

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
