#!/bin/bash

# Essential docker aliases for daily use

# Container operations
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dexec='docker exec -it'
alias dlogs='docker logs -f'
alias dstop='docker stop'
alias drm='docker rm'
alias drmf='docker rm -f'

# Images
alias di='docker images'
alias dpull='docker pull'
alias dbuild='docker build -t'
alias drmi='docker rmi'

# Docker compose (using v2 syntax)
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dcr='docker compose restart'
alias dcb='docker compose build'

# System cleanup
alias dprune='docker system prune -f'
alias dprunea='docker system prune -af'

# Useful functions

# Enter a running container
denter() {
    if [[ -z "$1" ]]; then
        echo "Usage: denter <container_name_or_id>"
        return 1
    fi
    docker exec -it "$1" /bin/bash || docker exec -it "$1" /bin/sh
}

# Clean up everything (containers, images, volumes)
dclean() {
    echo "Cleaning up Docker..."
    docker system prune -af --volumes
    echo "Cleanup complete!"
}

# Quick run with interactive terminal
drun() {
    docker run -it --rm "$@"
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