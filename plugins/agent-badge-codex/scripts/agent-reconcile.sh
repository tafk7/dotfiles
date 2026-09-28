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
# It never promotes. Promotion from a stale file would fight the hooks, which are
# both faster and more specific, and it would clobber `needs`/`done`/`waiting`
# with a state that cannot express them.
#
# Codex has no equivalent file, so its panes are left alone entirely.
#
# Usage: agent-reconcile.sh          (all panes)
# Called from tmux's pane-focus-in hook (installed by ../agent-badge.tmux), so
# it costs nothing when idle.

command -v jq >/dev/null 2>&1 || exit 0
[[ -n "$TMUX" ]] || exit 0

sessdir="$HOME/.claude/sessions"
[[ -d "$sessdir" ]] || exit 0

changed_panes=()

for f in "$sessdir"/*.json; do
    [[ -e "$f" ]] || continue

    read -r pid status tmuxref < <(
        jq -r '"\(.pid // "") \(.status // "") \(.tmux // "")"' "$f" 2>/dev/null
    )
    [[ -n "$pid" && -n "$status" && -n "$tmuxref" && "$tmuxref" != "null" ]] || continue

    # Session files outlive their sessions; a dead session's status must not
    # overwrite a pane tmux has since reused.
    kill -0 "$pid" 2>/dev/null || continue

    pane="%${tmuxref##*.%}"
    [[ "$pane" == "%" ]] && continue

    # Pane must still exist and still be running Claude.
    cmd=$(tmux display -p -t "$pane" '#{pane_current_command}' 2>/dev/null) || continue
    [[ "$cmd" == *claude* ]] || continue

    cur=$(tmux show -p -t "$pane" -qv @cc_pane_state 2>/dev/null)

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
done

# Rebuild once per affected pane. `reap` recomputes that pane's whole window, so
# this is one pass per changed window, not per pane in the window.
if (( ${#changed_panes[@]} )); then
    for p in "${changed_panes[@]}"; do
        "$(dirname -- "${BASH_SOURCE[0]}")/agent-status.sh" reap "$p" </dev/null 2>/dev/null
    done
    tmux refresh-client -S 2>/dev/null
fi

exit 0
