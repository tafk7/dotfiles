#!/bin/bash

# Essential docker aliases for daily use

# Container operations
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dexec='docker exec -it'
alias dlogs='docker logs -f'
alias dstop='docker stop'
alias drm='docker rm'

# Images
alias di='docker images'
alias dpull='docker pull'
alias dbuild='docker build -t'

# Docker compose (using v2 syntax)
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'

# System cleanup
alias dprune='docker system prune'      # Will prompt for confirmation
alias dprunea='docker system prune -a'  # Will prompt for confirmation