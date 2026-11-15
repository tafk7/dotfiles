#!/bin/bash
# Reconcile tmux badge state against Claude Code's own session files.
#
# Claude writes ~/.claude/sessions/<pid>.json per session, containing:
#   status            "busy" | "idle" | "waiting"   -- first-party, authoritative
#                     ("waiting" means a permission prompt is on screen)
#   tmux              "0:@14.%117"      -- session:@window.%pane
#   pid, statusUpdatedAt
#
# Hooks still drive the richer states (needs / compacting / waiting on
# subagents) because the file cannot express them, but when a hook is missed --
# an errored turn, a killed process, a harness crash -- this unsticks the badge.
#
# Deliberately DEMOTION-ONLY, for the states a missed hook strands:
#   file says idle + badge says working/thinking  -> demote to idle
#   file says busy + badge says needs             -> demote to working
#                                    (permission was granted; nothing fires on
#                                     grant, so `needs` would otherwise persist
#                                     for the whole tool run)
# It never promotes a state the hooks wrote. Promotion from a stale file would
# fight the hooks, which are both faster and more specific, and it would clobber
# `needs`/`done`/`waiting` with a state that cannot express them.
#
# The one exception is SEEDING a viewer pane the hooks have not written: a pane
# showing a background session (`claude attach`, or the agent view showing it)
# gets nothing until that session's next event, which may be an hour away. The
# session file's status is then the only reading there is:
#   busy -> working, idle -> idle, waiting -> needs   (never done)
# `waiting` is trusted here: it appears with the permission prompt (before the
# hook) and drops when the prompt goes. A viewer pane carries @cc_pane_session,
# because a background session's file has no `tmux` field, and @cc_pane_view;
# a pane seeded as a viewer that no longer resolves (the agent view back on its
# list) is cleared.
#
# Codex has no equivalent file, so its panes are left alone entirely.
#
# Usage: agent-reconcile.sh          (all panes)
#        agent-reconcile.sh seed P   (pane P only: the pane-title-changed hook)
# Called from tmux's pane-focus-in hook (installed by ../agent-badge.tmux), so
# it costs nothing when idle.

command -v jq >/dev/null 2>&1 || exit 0
[[ -n "$TMUX" ]] || exit 0

sessdir="$HOME/.claude/sessions"
[[ -d "$sessdir" ]] || exit 0

changed_panes=()
here="$(dirname -- "${BASH_SOURCE[0]}")"

seed_pane() {   # $1 = pane; appends to changed_panes
    local pane="$1" view f status sid st cur_sid
    read -r view f < <(bash "$here/agent-viewers.sh" session "$pane")
    if [[ -z "$f" ]]; then
        if [[ -n "$(tmux show -p -t "$pane" -qv @cc_pane_view 2>/dev/null)" ]]; then
            for o in @cc_pane_state @cc_pane_since @cc_pane_view @cc_pane_session; do
                tmux set -pu -t "$pane" "$o" 2>/dev/null
            done
            changed_panes+=("$pane")
        fi
        return
    fi
    read -r sid status < <(jq -r '"\(.sessionId // "") \(.status // "")"' "$f" 2>/dev/null)
    cur_sid=$(tmux show -p -t "$pane" -qv @cc_pane_session 2>/dev/null)
    # Same session and already badged: the hooks own it from here.
    [[ "$cur_sid" == "$sid" && -n "$(tmux show -p -t "$pane" -qv @cc_pane_state 2>/dev/null)" ]] && return
    case "$status" in
        busy)    st=working ;;
        idle)    st=idle ;;
        waiting) st=needs ;;
        *)       return ;;
    esac
    tmux set -p -t "$pane" @cc_pane_view "$view" 2>/dev/null
    tmux set -p -t "$pane" @cc_pane_session "$sid" 2>/dev/null
    tmux set -p -t "$pane" @cc_pane_state "$st" 2>/dev/null
    tmux set -p -t "$pane" @cc_pane_since "$(date +%s)" 2>/dev/null
    changed_panes+=("$pane")
}

finish() {
    if (( ${#changed_panes[@]} )); then
        for p in "${changed_panes[@]}"; do
            "$here/agent-status.sh" reap "$p" </dev/null 2>/dev/null
        done
        tmux refresh-client -S 2>/dev/null
    fi
    exit 0
}

# `seed <pane>`: one pane, from the pane-title-changed hook.
if [[ "$1" == seed && -n "$2" ]]; then
    seed_pane "$2"
    finish
fi

# Focus pass: seed every claude pane the hooks have not written. One tmux call
# when there is none, which is the steady state.
# The agent view on its list titles the pane "... claude agents"; skip it, the
# title hook seeds the agent view when it opens a session.
# Seeded viewer panes are also collected by session id, so the demotion pass
# below reaches them: a background session file has no `tmux` field.
declare -A seeded=() pcmd=() pstate=()
while IFS=$'\t' read -r p cmd st sid title; do
    pcmd["$p"]="$cmd"; [[ "$st" != - ]] && pstate["$p"]="$st"
    [[ "$sid" != - ]] && seeded["$sid"]+=" $p"
    [[ "$cmd" == claude && "$st" == - && "$title" != *"claude agents" ]] && seed_pane "$p"
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{?@cc_pane_state,#{@cc_pane_state},-}	#{?@cc_pane_session,#{@cc_pane_session},-}	#{pane_title}' 2>/dev/null)
# (read collapses adjacent tabs, so empty fields are printed as "-")

demote() {   # $1 = pane, $2 = session file status
    local pane="$1" status="$2" cur
    # Pane must still exist and still be running Claude (from the one
    # list-panes call above; a just-seeded pane's state is not in it, skip it).
    [[ "${pcmd[$pane]}" == *claude* ]] || return
    cur="${pstate[$pane]}"

    case "$status" in
        idle)
            case "$cur" in
                working|thinking)
                    tmux set -p -t "$pane" @cc_pane_state idle 2>/dev/null
                    changed_panes+=("$pane")
                    ;;
            esac
            ;;
        busy)
            # No hook fires when a permission is granted (there is no such event,
            # and PreToolUse runs before PermissionRequest), so `needs` would stay
            # lit for the whole tool run. The file reports "waiting" while a
            # prompt is pending and "busy" once the tool runs, so busy means the
            # decision has been made.
            case "$cur" in
                needs)
                    tmux set -p -t "$pane" @cc_pane_state working 2>/dev/null
                    changed_panes+=("$pane")
                    ;;
            esac
            ;;
    esac
    # No branch for status=waiting. Promoting to `needs` from here would catch a
    # missed PermissionRequest, but this stays demotion-only on purpose: a stale
    # read that invents an attention-demanding badge is worse than one that
    # fails to.
}

for f in "$sessdir"/*.json; do
    [[ -e "$f" ]] || continue

    read -r pid status sid tmuxref < <(
        jq -r '"\(.pid // "") \(.status // "") \(.sessionId // "") \(.tmux // "")"' "$f" 2>/dev/null
    )
    [[ -n "$pid" && -n "$status" ]] || continue

    # Session files outlive their sessions; a dead session's status must not
    # overwrite a pane tmux has since reused.
    kill -0 "$pid" 2>/dev/null || continue

    panes="${seeded[$sid]}"
    if [[ -n "$tmuxref" && "$tmuxref" != "null" ]]; then
        pane="%${tmuxref##*.%}"
        [[ "$pane" != "%" ]] && panes+=" $pane"
    fi
    for pane in $panes; do demote "$pane" "$status"; done
done

# Rebuild once per affected pane. `reap` recomputes that pane's whole window, so
# this is one pass per changed window, not per pane in the window.
finish
