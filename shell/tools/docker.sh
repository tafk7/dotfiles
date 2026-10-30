#!/bin/bash
# Docker — aliases and functions

# Container operations
alias dps='docker ps'          # List running containers
alias dpsa='docker ps -a'      # List all containers (including stopped)
alias dexec='docker exec -it'  # Exec into a running container
alias dlogs='docker logs -f'   # Tail container logs
alias dstop='docker stop'      # Stop a container
alias drm='docker rm'          # Remove a stopped container

# Images
alias di='docker images'        # List images
alias dpull='docker pull'       # Pull image from registry
alias dbuild='docker build -t'  # Build image with tag

# Docker compose (using v2 syntax)
alias dc='docker compose'           # Run docker compose command
alias dcu='docker compose up -d'    # Start services in background
alias dcd='docker compose down'     # Stop and remove containers
alias dcl='docker compose logs -f'  # Tail logs from all services

# System cleanup
alias dprune='docker system prune'      # Remove unused containers and images (asks first)
alias dprunea='docker system prune -a'  # Remove all unused Docker resources (asks first)

# Open a bash shell in a running container (sh where there is no bash)
denter() {
    if [[ -z "$1" ]]; then
        echo "Usage: denter <container_name_or_id>"
        return 1
    fi
    if [[ ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        echo "Error: Invalid container name or ID"
        return 1
    fi
    docker exec -it "$1" /bin/bash || docker exec -it "$1" /bin/sh
}

# Stop all running containers
dstopall() {
    local -a containers=()
    local container
    while IFS= read -r container; do
        [[ -n "$container" ]] && containers+=("$container")
    done < <(docker ps -q)
    if (( ${#containers[@]} )); then
        docker stop "${containers[@]}"
    else
        echo "No running containers"
    fi
}
