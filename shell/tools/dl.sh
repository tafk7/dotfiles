# shellcheck shell=bash
# Tab completion in bash for bin/dl: its options after "-", else files here and
# the relative names it would find through DL_PATH; and for bin/up, its DEST
# (its first word is a Windows path, which this machine can't see). zsh
# completes files.

[[ -n "${BASH_VERSION:-}" ]] || return 0

_dl_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}" dir name
    local -a dirs=()
    COMPREPLY=()
    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W '--wezterm --wezterm-config --print --help' -- "$cur")
        return 0
    fi
    mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    [[ "$cur" == /* || "$cur" == ~* ]] && return 0
    IFS=: read -r -a dirs <<< "${DL_PATH:-}"
    for dir in "${dirs[@]}"; do
        [[ -n "$dir" && -d "$dir" ]] || continue
        while IFS= read -r name; do
            [[ -d "$name" ]] && name="$name/"
            COMPREPLY+=("${name#"$dir"/}")
        done < <(compgen -f -- "$dir/$cur")
    done
    # A directory from DL_PATH ends in "/": keep the cursor there to go on.
    [[ ${#COMPREPLY[@]} -eq 1 && "${COMPREPLY[0]}" == */ ]] && compopt -o nospace 2>/dev/null
    return 0
}
complete -o filenames -F _dl_complete dl

_up_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=()
    if (( COMP_CWORD == 2 )); then
        mapfile -t COMPREPLY < <(compgen -f -- "$cur")
    elif (( COMP_CWORD == 1 )) && [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W '--help' -- "$cur")
    fi
    return 0
}
complete -o filenames -F _up_complete up
