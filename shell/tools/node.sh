#!/bin/bash
# Node.js and npm development aliases - essentials only

# Core npm commands
alias ni='npm install'
alias nr='npm run'
alias nrm='rm -rf node_modules'
alias nuke-node='rm -rf node_modules package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml'

# Common npm scripts - use nr prefix to be explicit
alias nrd='npm run dev'
alias nrb='npm run build'
alias nrt='npm run test'
alias nrs='npm run start'

# Clean reinstall. Preserve the lockfile and use its reproducible install mode.
nclean() {
    rm -rf node_modules
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
        npm ci
    else
        npm install
    fi
}
