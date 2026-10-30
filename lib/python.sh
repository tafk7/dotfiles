#!/bin/bash
# The Python for tools that need 3.11 or newer (tomllib): keys. The system
# python3 when it is new enough; else one uv manages, which setup installs where
# the system's is older (configure_uv_python; Ubuntu 22.04 has 3.10). The choice
# is cached, so a tool starts as fast as it would on the system Python, and
# DOTFILES_PYTHON overrides it.
#
#   dotfiles_python        print the interpreter, or explain and fail
#   dotfiles_python_find   find one afresh, uncached and quiet

[[ -n "${_DOTFILES_PYTHON_LOADED:-}" ]] && return 0
_DOTFILES_PYTHON_LOADED=1

DOTFILES_PYTHON_MIN=3.11

# PYTHON is at least DOTFILES_PYTHON_MIN.
_python_new_enough() {
    "$1" -c "import sys; sys.exit(sys.version_info < (${DOTFILES_PYTHON_MIN/./, }))" 2>/dev/null
}

dotfiles_python_find() {
    local py
    if py="$(command -v python3 2>/dev/null)" && _python_new_enough "$py"; then
        printf '%s\n' "$py"
        return 0
    fi
    # --no-project: a project's .python-version in the current directory must not
    # pick an older one.
    command -v uv >/dev/null 2>&1 || return 1
    py="$(uv python find --no-project ">=$DOTFILES_PYTHON_MIN" 2>/dev/null)" && [[ -x "$py" ]] || return 1
    printf '%s\n' "$py"
}

dotfiles_python() {
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/python" py
    if [[ -n "${DOTFILES_PYTHON:-}" ]]; then
        printf '%s\n' "$DOTFILES_PYTHON"
        return 0
    fi
    if [[ -r "$cache" ]] && IFS= read -r py < "$cache" && [[ -x "$py" ]]; then
        printf '%s\n' "$py"
        return 0
    fi
    if ! py="$(dotfiles_python_find)"; then
        printf 'Python %s or newer is needed. The system has %s; install one with: uv python install 3.12\n' \
            "$DOTFILES_PYTHON_MIN" "$(python3 --version 2>/dev/null || echo 'no python3')" >&2
        return 1
    fi
    mkdir -p "${cache%/*}" 2>/dev/null && printf '%s\n' "$py" > "$cache" 2>/dev/null
    printf '%s\n' "$py"
}
