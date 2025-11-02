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

# Useful functions

# Enter a running container (with proper escaping)
denter() {
    if [[ -z "$1" ]]; then
        echo "Usage: denter <container_name_or_id>"
        return 1
    fi
    # Validate container name/id format
    if [[ ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        echo "Error: Invalid container name or ID"
        return 1
    fi
    docker exec -it "$1" /bin/bash || docker exec -it "$1" /bin/sh
}

# Stop all running containers
dstopall() {
    local containers=$(docker ps -q)
    if [[ -n "$containers" ]]; then
        docker stop $containers
    else
        echo "No running containers"
    fi
}