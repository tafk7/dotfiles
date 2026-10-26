#!/bin/bash
# Each interactive shell records when it loaded its startup files, so refresh
# and verify can tell which shells predate a change (lib/staleness.sh).
# $XDG_RUNTIME_DIR/dotfiles/shells/PID-START holds "LOADED<TAB>MODE"; START,
# the process start time, tells a reused pid apart. A real reload is a new
# shell image in the same process and rewrites the record; `reload --soft`
# keeps the old load time and marks it soft, since re-sourcing adds and
# changes definitions but cannot remove them. Builtins only: this runs at
# every interactive start.

_dotfiles_shell_record() {
    [[ -n "${XDG_RUNTIME_DIR:-}" && -r /proc/$$/stat ]] || return 0
    local dir="$XDG_RUNTIME_DIR/dotfiles/shells" stat rest now loaded mode=full
    local -a fields
    IFS= read -r stat < /proc/$$/stat || return 0
    rest="${stat##*) }"
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null
        # shellcheck disable=SC2296,SC2206  # zsh word splitting
        fields=(${=rest})
        # zsh arrays start at 1: the start time is field 22, the 20th after comm.
        local start="${fields[20]}"
    else
        # shellcheck disable=SC2206
        fields=($rest)
        local start="${fields[19]}"
    fi
    now="${EPOCHSECONDS:-}"
    [[ -n "$now" && -n "$start" ]] || return 0
    [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null || return 0
    loaded="$now"
    if [[ -n "${_DOTFILES_SOFT_RELOAD:-}" && -r "$dir/$$-$start" ]]; then
        IFS=$'\t' read -r loaded _ < "$dir/$$-$start" || loaded="$now"
        mode=soft
    fi
    printf '%s\t%s\n' "$loaded" "$mode" > "$dir/$$-$start" 2>/dev/null
    unset _DOTFILES_SOFT_RELOAD
}
_dotfiles_shell_record
