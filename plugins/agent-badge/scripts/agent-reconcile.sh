#!/bin/bash
# Reconcile tmux badge state against Claude Code's own session files.
#
# Claude writes ~/.claude/sessions/<pid>.json per session, containing:
#   status            "busy" | "idle"   -- first-party, authoritative
#   tmux              "0:@14.%117"      -- session:@window.%pane
#   pid, statusUpdatedAt
#
# That is ground truth, and it makes every heuristic we would otherwise need
# unnecessary. Hooks still drive the rich states (needs / busy-compacting /
# waiting-on-subagents) because the file only knows busy-vs-idle -- but when a
# hook is *missed*, this is what unsticks the badge. Missed hooks are not
# hypothetical: an errored turn, a killed process, or a harness crash all leave
# the last hook state pinned forever.
#
# Deliberately DEMOTION-ONLY, and only for the two states a missed hook strands:
#   file says idle + badge says working/thinking  -> demote to idle
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

    # Stale files outlive their sessions -- some here were days old. Without this
    # a dead session's last-known status would keep overwriting a live pane that
    # tmux has since reused for something else.
    kill -0 "$pid" 2>/dev/null || continue

    pane="%${tmuxref##*.%}"
    [[ "$pane" == "%" ]] && continue

    # Pane must still exist and still be running Claude.
    cmd=$(tmux display -p -t "$pane" '#{pane_current_command}' 2>/dev/null) || continue
    [[ "$cmd" == *claude* ]] || continue

    cur=$(tmux show -p -t "$pane" -qv @cc_pane_state 2>/dev/null)

    if [[ "$status" == "idle" ]]; then
        case "$cur" in
            working|thinking)
                tmux set -p -t "$pane" @cc_pane_state idle 2>/dev/null
                changed_panes+=("$pane")
                ;;
        esac
    fi
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
