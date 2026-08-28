#!/usr/bin/env bash
# agent-badge.tmux -- tmux-side wiring for the agent-badge plugin.
#
# Installs two things into the running tmux server:
#   1. the badge placeholder #{E:@cc_win_badge} in the window status formats
#   2. the pane-focus-in / pane-exited hooks that keep badges honest
#
# Called from two places, deliberately:
#
#   PRIMARY -- ~/.tmux.conf does `run-shell "<plugin>/agent-badge.tmux"`.
#     Explicit, greppable, and runs once at config load. This is the supported
#     path on a machine that has the dotfiles.
#
#   FALLBACK -- agent-status.sh calls this when it notices the badge is missing
#     from window-status-format. That covers two cases: a machine where only the
#     plugin is installed and tmux.conf knows nothing about it, and a `prefix+r`
#     reload, which resets window-status-format to the file's value and so
#     strips the badge (verified: source-file overwrites the option outright).
#
# Everything here is idempotent, because both callers can fire repeatedly --
# SessionStart alone re-fires on every compaction and resume.
#
# Usage: agent-badge.tmux [wire|unwire]     (default: wire)

set -u

SELF_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATUS="$SELF_DIR/scripts/agent-status.sh"
RECONCILE="$SELF_DIR/scripts/agent-reconcile.sh"

BADGE='#{E:@cc_win_badge}'
FORMATS="window-status-format window-status-current-format"

# Any hook command mentioning one of these is ours. Used both to avoid adding a
# second copy and to recognise a *stale* copy left by an older install at a
# different path -- plugin caches are version-pinned
# (cache/<marketplace>/<plugin>/<version>/) and the old directory is swept, so a
# plugin update silently breaks hooks that still point at it.
OURS_RE='agent-(status|reconcile)\.sh'

command -v tmux >/dev/null 2>&1 || exit 0
[[ -n "${TMUX:-}" ]] || tmux has-session 2>/dev/null || exit 0

# #{E:...} (expand a format stored in an option) landed in tmux 3.2. Below that
# the badge option would render as literal text across every window, which is
# worse than no badge at all.
ver=$(tmux -V 2>/dev/null | sed 's/^tmux //; s/[^0-9.].*$//')
major=${ver%%.*}
minor=${ver#*.}; minor=${minor%%.*}
[[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || exit 0
(( major > 3 || (major == 3 && minor >= 2) )) || exit 0

# --------------------------------------------------------------------------
# Hook table. Order within pane-focus-in is not load-bearing -- each action
# recomputes the whole window badge before exiting, so they converge whatever
# order they run in -- but it is kept stable for readability.
# --------------------------------------------------------------------------
hook_cmds() {
    case "$1" in
        pane-focus-in)
            printf '%s\n' \
                "run-shell -b \"$STATUS seen #{pane_id}\"" \
                "run-shell -b \"$STATUS reap #{pane_id}\"" \
                "run-shell -b \"$RECONCILE\""
            ;;
        pane-exited)
            printf '%s\n' "run-shell -b \"$STATUS reap #{pane_id}\""
            ;;
    esac
}

# Drop every hook entry that is ours, by index. Unsetting an index leaves a hole
# rather than renumbering (verified), so indices stay valid while we iterate and
# the order of removal does not matter.
drop_ours() {
    local event="$1" line idx
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" =~ $OURS_RE ]] || continue
        idx="${line#*[}"; idx="${idx%%]*}"
        [[ "$idx" =~ ^[0-9]+$ ]] || continue
        tmux set-hook -gu "${event}[${idx}]" 2>/dev/null
    done < <(tmux show-hooks -g "$event" 2>/dev/null)
}

wire_formats() {
    local opt cur lead rest
    for opt in $FORMATS; do
        cur=$(tmux show -gv "$opt" 2>/dev/null) || continue
        case "$cur" in *"@cc_win_badge"*) continue ;; esac
        # Insert after any leading padding rather than at column 0, so the badge
        # sits inside the window cell's own margin instead of hard against the
        # cell to its left.
        lead="${cur%%[! ]*}"
        rest="${cur#"$lead"}"
        tmux set -g "$opt" "${lead}${BADGE}${rest}" 2>/dev/null
    done
}

wire_hooks() {
    local event cmd
    for event in pane-focus-in pane-exited; do
        drop_ours "$event"
        while IFS= read -r cmd; do
            [[ -n "$cmd" ]] || continue
            tmux set-hook -ga "$event" "$cmd" 2>/dev/null
        done < <(hook_cmds "$event")
    done
}

case "${1:-wire}" in
wire)
    # Two independent guards, because the two halves fail differently.
    #
    # Formats are reset by every `source-file`, so they are checked by content
    # on every call -- one `show -gv` in the steady state.
    #
    # Hooks survive a reload and *accumulate* on re-append (verified: 1 -> 2 -> 3
    # over three sources), so re-running the append unguarded is the classic
    # multiplying-handler bug. @cc_badge_wired records which plugin directory
    # last wired this server: a plain reload short-circuits here, while an
    # install at a new path (plugin update, or dotfiles replacing a cache copy)
    # falls through and re-points the hooks.
    wire_formats
    if [[ "$(tmux show -gv @cc_badge_wired 2>/dev/null)" != "$SELF_DIR" ]]; then
        wire_hooks
        tmux set -g @cc_badge_wired "$SELF_DIR" 2>/dev/null
    fi
    tmux refresh-client -S 2>/dev/null
    ;;
unwire)
    # Neither harness fires a hook on plugin uninstall, so this has to be run by
    # hand. Without it the tmux server keeps invoking a deleted path on every
    # pane focus until the server is restarted.
    for event in pane-focus-in pane-exited; do drop_ours "$event"; done
    for opt in $FORMATS; do
        cur=$(tmux show -gv "$opt" 2>/dev/null) || continue
        tmux set -g "$opt" "${cur//"$BADGE"/}" 2>/dev/null
    done
    tmux set -gu @cc_badge_wired 2>/dev/null
    while IFS= read -r w; do
        [[ -n "$w" ]] || continue
        tmux set -wu -t "$w" @cc_win_badge 2>/dev/null
        tmux set -wu -t "$w" @cc_win_state 2>/dev/null
    done < <(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        tmux set -pu -t "$p" @cc_pane_state 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_since 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_agents 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_prev 2>/dev/null
    done < <(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
    tmux refresh-client -S 2>/dev/null
    ;;
*)
    exit 0
    ;;
esac

exit 0
