#!/bin/bash
# Docker functions (extracted from shell/aliases/docker.sh)

# Enter a running container
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
    local containers=$(docker ps -q)
    if [[ -n "$containers" ]]; then
        docker stop $containers
    else
        echo "No running containers"
    fi
}
