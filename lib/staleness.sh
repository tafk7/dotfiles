#!/bin/bash
# Which running shells and programs predate a change dotfiles made. Persistent:
# change events live in state (change_record, lib/state.sh) and each shell's
# load record under $XDG_RUNTIME_DIR (shell/staleness.sh), so a second refresh
# still lists what has not restarted. A change dotfiles did not make (a hand
# edit of ~/.shell.local or ~/.shell.env) has no event, so shells loaded before
# it are "possibly stale". Prints outcome records (lib/outcomes.sh).

[[ -n "${_DOTFILES_STALENESS_LOADED:-}" ]] && return 0
_DOTFILES_STALENESS_LOADED=1

# Programs whose processes are checked against their consumer's change event:
# consumer, then the process names (comm) that run it.
STALE_PROGRAMS=("claude claude" "codex codex" "opencode opencode" "neovim nvim" "tmux tmux:")

# proc_start_epoch PID: when the process started, in epoch seconds.
proc_start_epoch() {
    local stat rest btime ticks
    local -a fields
    IFS= read -r stat < "/proc/$1/stat" 2>/dev/null || return 1
    rest="${stat##*) }"
    read -ra fields <<< "$rest"
    btime="$(awk '$1 == "btime" { print $2 }' /proc/stat)"
    ticks="$(getconf CLK_TCK 2>/dev/null || echo 100)"
    printf '%s\n' "$(( btime + fields[19] / ticks ))"
}

# proc_start_ticks PID: the raw start time a shell record's name carries.
proc_start_ticks() {
    local stat rest
    local -a fields
    IFS= read -r stat < "/proc/$1/stat" 2>/dev/null || return 1
    rest="${stat##*) }"
    read -ra fields <<< "$rest"
    printf '%s\n' "${fields[19]}"
}

# staleness_report [--sweep]: records for shells and programs. --sweep (refresh)
# removes records of shells that have exited or whose pid was reused.
staleness_report() {
    local sweep="${1:-}" section=Running dir="${XDG_RUNTIME_DIR:-}/dotfiles/shells"
    local record name pid start loaded mode event="" reason="" tracked=0 file
    local -a stale=() soft=() possibly=()
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        outcome advisory "$section" shells "not tracked: XDG_RUNTIME_DIR is unset"
    else
        IFS=$'\t' read -r _ event reason < <(change_line shell 2>/dev/null || true) || true
        for record in "$dir"/*; do
            [[ -f "$record" ]] || continue
            name="${record##*/}" pid="${name%%-*}" start="${name#*-}"
            if [[ "$(proc_start_ticks "$pid" 2>/dev/null)" != "$start" ]]; then
                [[ "$sweep" != --sweep ]] || rm -f "$record"
                continue
            fi
            tracked=$(( tracked + 1 ))
            IFS=$'\t' read -r loaded mode < "$record" || continue
            if [[ -n "$event" ]] && (( loaded < event )); then
                if [[ "$mode" == soft ]]; then soft+=("$pid"); else stale+=("$pid"); fi
                continue
            fi
            for file in "$HOME/.shell.local" "$HOME/.shell.env"; do
                [[ -f "$file" ]] && (( $(stat -c %Y "$file") > loaded )) && { possibly+=("$pid"); break; }
            done
        done
        (( ${#stale[@]} == 0 )) || outcome advisory "$section" shells \
            "${#stale[@]} loaded before the last change to shell startup ($reason); reload them: pids ${stale[*]}"
        (( ${#soft[@]} == 0 )) || outcome advisory "$section" shells \
            "${#soft[@]} soft-reloaded after the last change, which cannot remove old definitions; reload them: pids ${soft[*]}"
        (( ${#possibly[@]} == 0 )) || outcome advisory "$section" shells \
            "${#possibly[@]} possibly stale: ~/.shell.local or ~/.shell.env changed after they loaded: pids ${possibly[*]}"
        (( ${#stale[@]} + ${#soft[@]} + ${#possibly[@]} > 0 )) || outcome ok "$section" shells "$tracked tracked, all current"
    fi

    local entry consumer comm proc found
    for entry in "${STALE_PROGRAMS[@]}"; do
        read -r consumer comm <<< "$entry"
        IFS=$'\t' read -r _ event reason < <(change_line "$consumer" 2>/dev/null || true) || continue
        [[ -n "$event" ]] || continue
        found=()
        for proc in /proc/[0-9]*; do
            # A process can exit between the glob and the read.
            { IFS= read -r name < "$proc/comm"; } 2>/dev/null || continue
            [[ "$name" == "$comm" || ( "$comm" == *: && "$name" == "$comm"* ) ]] || continue
            start="$(proc_start_epoch "${proc#/proc/}" 2>/dev/null)" || continue
            (( start < event )) && found+=("${proc#/proc/}")
        done
        (( ${#found[@]} == 0 )) || outcome advisory "$section" "$consumer" \
            "${#found[@]} process(es) started before $consumer changed ($reason); restart them: pids ${found[*]}"
    done
    return 0
}
