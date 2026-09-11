#!/bin/bash
# Process management functions

# Process search
psg() {
    if [[ -z "$1" ]]; then
        echo "Usage: psg <process_name>"
        echo "Search for running processes matching the given name"
        return 1
    fi
    ps aux | grep -v grep | grep -i "$1"
}

# Find and kill process (requires fzf)
fkill() {
    local signal=TERM pid
    if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
        signal=KILL
        shift
    fi
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if [[ -n $pid ]]; then
        while IFS= read -r selected; do
            [[ "$selected" =~ ^[0-9]+$ ]] && kill -s "$signal" "$selected"
        done <<< "$pid"
    fi
}

# Find and kill process listening on a port
killport() {
    if [[ -z "$1" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        echo "Usage: killport [-f|--force] <port>"
        echo "Find and kill the process listening on a given port."
        echo "Shows process details and asks for confirmation unless --force is used."
        return 1
    fi

    local force=false
    local port
    for arg in "$@"; do
        case "$arg" in
            -f|--force) force=true ;;
            *) port="$arg" ;;
        esac
    done

    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        echo "Error: invalid port number '$port'"
        return 1
    fi

    local pid
    pid=$(lsof -i :"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)

    if [[ -z "$pid" ]]; then
        echo "No process listening on port $port"
        return 1
    fi

    local details
    details=$(ps -p "$pid" -o pid=,user=,comm=,args= 2>/dev/null)
    echo "Port $port is held by:"
    echo "  PID:  $pid"
    echo "  $details"

    if $force; then
        kill -KILL "$pid"
        echo "Force-killed PID $pid"
    else
        read -rp "Kill this process? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            kill -TERM "$pid"
            echo "Sent TERM to PID $pid"
        else
            echo "Aborted"
        fi
    fi
}

# Extract various archive types
extract() {
    if [[ -f $1 ]]; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.tar.xz)    tar xJf "$1"     ;;
            *.tar.zst)   tar --zstd -xf "$1" ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.xz)        unxz "$1"        ;;
            *.zst)       unzstd "$1"      ;;
            *.lzma)      unlzma "$1"      ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}
