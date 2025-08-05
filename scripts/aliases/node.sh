#!/bin/bash
# Node.js and npm development aliases - essentials only

# Core npm commands
alias ni='npm install'
alias nr='npm run'
alias nrm='rm -rf node_modules package-lock.json'

# Common npm scripts - use nr prefix to be explicit
alias nrd='npm run dev'
alias nrb='npm run build'
alias nrt='npm run test'
alias nrs='npm run start'

# Clean reinstall
alias nclean='nrm && npm install'