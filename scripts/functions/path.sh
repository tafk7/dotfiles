#!/bin/bash
# PATH management functions

# Add directory to PATH if it exists and isn't already in PATH
add_to_path() {
    local dir="$1"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
    fi
}

# Remove duplicates from PATH
dedupe_path() {
    local new_path=""
    local IFS=':'
    for dir in $PATH; do
        if [[ ":$new_path:" != *":$dir:"* ]]; then
            new_path="${new_path:+$new_path:}$dir"
        fi
    done
    export PATH="$new_path"
}

# Show PATH entries one per line
show_path() {
    echo "$PATH" | tr ':' '\n'
}