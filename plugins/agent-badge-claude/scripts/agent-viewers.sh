#!/bin/bash
# Map between tmux panes and the background Claude sessions (`claude --bg`)
# they show. Such a session runs under the daemon with no pane of its own; the
# pane belongs to whichever viewer process is showing it.
#
#   agent-viewers.sh panes <session-id>   "<pane> <view>" per pane viewing it
#   agent-viewers.sh session <pane>       "<view> <session-file>" for the session
#                                         that pane views (view: attach|agents)
#
# Two kinds of viewer, each a foreground `claude` process in the pane:
#   attach   `claude attach <arg>`. <arg> resolves as the CLI resolves it: the
#            short jobId, a sessionId prefix, or a case-insensitive part of the
#            name (an exact name first). A name part matching more than one live
#            session resolves to nothing: a wrong badge is worse than none.
#   agents   `claude agents`, the agent view. Its argv never names the session,
#            but while it shows one it titles the pane with that session's name
#            (observed on 2.1.325; its list view titles the pane "... claude
#            agents"). Matched on the exact name, only when one live session has it.
#
# The tmux server is $TMUX's socket when set, else the default socket. Session
# files are read on every call: /rename changes a name under a running viewer.

sessdir="$HOME/.claude/sessions"

# Live session files as "file<TAB>sessionId<TAB>jobId<TAB>name", once per call.
load_sessions() {
    local f pid sid job name
    for f in "$sessdir"/*.json; do
        [[ -e "$f" ]] || continue
        IFS=$'\t' read -r pid sid job name < <(
            jq -r '[.pid // "", .sessionId // "", .jobId // "", .name // ""] | @tsv' "$f" 2>/dev/null)
        if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then continue; fi
        printf '%s\t%s\t%s\t%s\n' "$f" "$sid" "$job" "$name"
    done
}

# $1=view $2=arg; stdin = load_sessions. Prints the one matching file, or nothing.
resolve() {
    local view="$1" arg="$2" lc="${2,,}" f sid job name exact="" hits=()
    [[ -n "$arg" ]] || return 0
    while IFS=$'\t' read -r f sid job name; do
        if [[ "$view" == agents ]]; then
            [[ "$name" == "$arg" ]] && hits+=("$f")
        elif [[ "${job,,}" == "$lc" || "${sid,,}" == "$lc"* || "${name,,}" == "$lc" ]]; then
            [[ -z "$exact" ]] && exact="$f" || exact=ambiguous
        elif [[ -n "$name" && "${name,,}" == *"$lc"* ]]; then
            hits+=("$f")
        fi
    done
    [[ "$exact" == ambiguous ]] && return 0
    if [[ -n "$exact" ]]; then
        printf '%s\n' "$exact"
    elif (( ${#hits[@]} == 1 )); then
        printf '%s\n' "${hits[0]}"
    fi
}

# "<pane> <view> <arg>" per pane whose foreground is a viewing `claude`.
# $1 = only this pane (optional).
viewer_panes() {
    local only="$1" pane tty title stat args argv
    local -A tty_pane=() pane_title=()
    while IFS=$'\t' read -r pane tty title; do
        [[ -z "$only" || "$pane" == "$only" ]] || continue
        tty_pane["${tty#/dev/}"]="$pane"
        pane_title["$pane"]="$title"
    done < <(tmux list-panes -a -F '#{pane_id}	#{pane_tty}	#{pane_title}' 2>/dev/null)
    (( ${#tty_pane[@]} )) || return 0
    while read -r tty stat args; do
        [[ "$stat" == *+* ]] || continue
        pane="${tty_pane[$tty]}"
        [[ -n "$pane" ]] || continue
        read -ra argv <<<"$args"     # split without globbing a name like "a*"
        [[ "${argv[0]##*/}" == claude ]] || continue
        if [[ "${argv[1]}" == attach && -n "${argv[2]}" ]]; then
            # A quoted name with spaces arrives as several words: keep them all.
            printf '%s attach %s\n' "$pane" "${args#*attach }"
        elif [[ "${argv[1]}" == agents && " ${argv[*]} " != *" --json "* ]]; then
            printf '%s agents %s\n' "$pane" "${pane_title[$pane]}"
        fi
    done < <(ps -e -o tty=,stat=,args= 2>/dev/null)
}

command -v jq >/dev/null 2>&1 || exit 0
case "$1" in
    panes)
        want="$2"; [[ -n "$want" ]] || exit 0
        vp=$(viewer_panes) ; [[ -n "$vp" ]] || exit 0
        sessions=$(load_sessions)
        while read -r pane view arg; do
            f=$(resolve "$view" "$arg" <<<"$sessions")
            [[ -n "$f" ]] || continue
            [[ "$(jq -r '.sessionId // empty' "$f" 2>/dev/null)" == "$want" ]] && printf '%s %s\n' "$pane" "$view"
        done <<<"$vp"
        ;;
    session)
        want="$2"; [[ -n "$want" ]] || exit 0
        read -r pane view arg < <(viewer_panes "$want")
        [[ -n "$pane" ]] || exit 0
        f=$(load_sessions | resolve "$view" "$arg")
        printf '%s %s\n' "$view" "$f"
        ;;
esac
exit 0
