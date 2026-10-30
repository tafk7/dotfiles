#!/bin/bash
# Node.js and npm development aliases - essentials only

# Core npm commands
alias ni='npm install'  # Install dependencies
alias nr='npm run'  # Run npm script
alias nrm='rm -rf node_modules'  # Delete node_modules (preserve lockfiles)
alias nuke-node='rm -rf node_modules package-lock.json npm-shrinkwrap.json yarn.lock pnpm-lock.yaml'  # Delete node_modules and lockfiles explicitly

# Common npm scripts - use nr prefix to be explicit
alias nrd='npm run dev'    # Run dev server
alias nrb='npm run build'  # Run build
alias nrt='npm run test'   # Run tests
alias nrs='npm run start'  # Run start

# Clean reinstall: delete node_modules, then npm ci (or npm install without a lockfile)
nclean() {
    rm -rf node_modules
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
        npm ci
    else
        npm install
    fi
}
