#!/bin/bash
# The operation lock: one state-changing dotfiles command at a time.
#
# A command re-execs itself under `flock -o`, so the lock descriptor is closed
# before the command runs and no descendant (a vendor installer, a surviving
# background process) can inherit it; the flock process releases it when the
# command exits. The holder records its run id and pid in the lock file and
# exports DOTFILES_OPERATION. A dotfiles command started inside the operation
# joins it when that id matches and the holder is alive, and never takes or
# releases the lock itself. The state lock in lib/state.sh still guards the
# individual writes inside an operation.

[[ -n "${_DOTFILES_OPERATION_LOADED:-}" ]] && return 0
_DOTFILES_OPERATION_LOADED=1

DOTFILES_OPERATION_LOCK="${DOTFILES_OPERATION_LOCK:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/operation.lock}"
# The exit status of a command refused because another operation is running.
DOTFILES_OPERATION_BUSY=75

# The lock file's fields: run id, holder pid, command.
_operation_holder() {
    local id="" pid="" command=""
    [[ -r "$DOTFILES_OPERATION_LOCK" ]] && IFS=$'\t' read -r id pid command < "$DOTFILES_OPERATION_LOCK"
    printf '%s\t%s\t%s\n' "$id" "$pid" "$command"
}

# Whether this process runs inside an operation it may join.
operation_joined() {
    local id pid _
    [[ -n "${DOTFILES_OPERATION:-}" ]] || return 1
    IFS=$'\t' read -r id pid _ <<< "$(_operation_holder)"
    [[ "$id" == "$DOTFILES_OPERATION" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

# Whether this process is the operation's holder (also after a re-exec, which
# keeps the pid).
operation_held_here() {
    local id pid _
    IFS=$'\t' read -r id pid _ <<< "$(_operation_holder)"
    [[ -n "${DOTFILES_OPERATION:-}" && "$id" == "$DOTFILES_OPERATION" && "$pid" == "$$" ]]
}

# Whether another operation holds the lock right now.
operation_busy() {
    [[ -e "$DOTFILES_OPERATION_LOCK" ]] || return 1
    ! flock -n -o "$DOTFILES_OPERATION_LOCK" true 2>/dev/null
}

operation_describe_holder() {
    local id pid command
    IFS=$'\t' read -r id pid command <<< "$(_operation_holder)"
    printf '%s (pid %s, run %s)\n' "${command:-unknown command}" "${pid:-unknown}" "${id:-unknown}"
}

# operation_begin SCRIPT [ARGS...]: return once this process holds or has
# joined the operation. Otherwise re-exec SCRIPT with ARGS under the lock, or
# exit DOTFILES_OPERATION_BUSY when another operation holds it.
operation_begin() {
    local script="$1" id
    shift
    if [[ -n "${DOTFILES_OPERATION_TAKING:-}" && "${DOTFILES_OPERATION_TAKING}" == "${DOTFILES_OPERATION:-}" ]]; then
        # Running under flock: record this process as the holder.
        unset DOTFILES_OPERATION_TAKING
        printf '%s\t%s\t%s\n' "$DOTFILES_OPERATION" "$$" "${script##*/}${*:+ $*}" > "$DOTFILES_OPERATION_LOCK" || return 1
        return 0
    fi
    operation_joined && return 0
    if ! command -v flock >/dev/null 2>&1; then
        printf 'Warning: flock is unavailable; running without the operation lock\n' >&2
        return 0
    fi
    mkdir -p "$(dirname "$DOTFILES_OPERATION_LOCK")" || return 1
    if operation_busy; then
        printf 'Another dotfiles operation is running: %s\n' "$(operation_describe_holder)" >&2
        exit "$DOTFILES_OPERATION_BUSY"
    fi
    id="$(date +%Y%m%dT%H%M%S)-$$-${RANDOM}"
    export DOTFILES_OPERATION="$id" DOTFILES_OPERATION_TAKING="$id"
    exec flock -n -o -E "$DOTFILES_OPERATION_BUSY" "$DOTFILES_OPERATION_LOCK" "$BASH" "$script" "$@"
}

# Whether ARGS ask only for help, a listing, a check, or a preview, which do
# not change state and so do not take the lock.
operation_read_only_args() {
    local arg
    for arg in "$@"; do
        case "$arg" in --help|-h|--dry-run|--check|--check-plugin|--list|-l) return 0 ;; esac
    done
    return 1
}
