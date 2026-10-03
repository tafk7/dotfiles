#!/bin/bash
# Coding-agent -> tmux window badge  (Claude Code + Codex CLI)
#
# Writes the calling pane's agent state into tmux user options, aggregates the
# per-pane states up to a window-level option, and forces a status redraw.
# window-status-format renders the pre-built badge.
#
# Usage: agent-status.sh <state> [pane]  state = working|done|needs|idle|busy|
#                                                thinking|tool|reap|gone
#
# Wired from per-harness hooks/hooks.json files and from the tmux server's
# pane-focus-in / pane-exited hooks installed by ../agent-badge.tmux.
#
# Agent-agnostic by design: the only agent-specific thing here is AGENT_CMDS,
# the list of process names that count as a live agent pane.
#
# The optional [pane] argument exists because an agent hook inherits $TMUX_PANE,
# but a tmux-spawned hook gets only $TMUX, so tmux passes #{pane_id} explicitly.
#
# Contract: never block the agent, never write to stdout (hook stdout can be
# interpreted), always exit 0.

# Process names that count as an agent pane. A pane running anything else has
# its state pruned -- quitting an agent drops back to a shell without killing the
# pane, so nothing else would ever clear the stale glyph.
AGENT_CMDS="claude codex"

state="$1"
pane="${2:-$TMUX_PANE}"

[[ -n "$TMUX" && -n "$pane" ]] || exit 0

if ! command -v jq >/dev/null 2>&1; then
    if [[ "$state" == session-start ]]; then
        printf 'agent-badge: jq is required on PATH; see the plugin README.\n' >&2
    fi
    exit 0
fi

# SessionStart must check both formats and hook ownership: the badge can remain
# visible while a plugin update deletes the cache directory stored in tmux's
# hooks. Focus events also repair a format removed by a tmux config reload.
# The wiring script owns the version/path checks and preserves unrelated hooks.
case "$state" in
    session-start)
        "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/agent-badge.tmux" \
            >/dev/null 2>&1
        ;;
    seen)
        case "$(tmux show -gv window-status-format 2>/dev/null)" in
            *@cc_win_badge*) ;;
            *) "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/agent-badge.tmux" \
                   >/dev/null 2>&1 ;;
        esac
        ;;
esac

case "$state" in
    working|done|needs|idle) ;;
    tool) ;;   # a tool ran: means "working", but must never resurrect a finished turn
    reap) ;;   # pane died: recompute the window from survivors, write no state
    gone) ;;   # session ended: drop this pane's state, then recompute
    busy) ;;       # compacting/summarizing: distinct from a normal working turn
    thinking) ;;   # Codex mid-turn (its own glyph/colour, see glyph())
    sub-start|sub-stop) ;;  # background subagent spawned / finished
    seen) ;;   # window was focused: demote every done pane in it to idle
    uncompact) ;;  # PostCompact: restore whatever the pane was doing before
    session-start) ;;  # SessionStart, but only a *real* one (see below)
    *) exit 0 ;;
esac

# Read the payload only for events that need it, and always under a timeout: a
# plain `cat` blocks forever if stdin is neither a tty nor closed, leaving a
# stuck process behind for every hook invocation.
payload=""
if [[ "$state" == sub-start || "$state" == sub-stop || "$state" == tool \
   || "$state" == session-start ]] && [[ ! -t 0 ]]; then
    payload=$(timeout 2 cat 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# Background subagents
#
# SubagentStop fires even for agents that outlive the parent turn, so the parent
# pane can legitimately be "done" while work is still in flight.
#
# Track live agent IDs as a set rather than a counter. Events carry no ordering
# guarantee and a Stop can arrive for an ID never seen (e.g. an agent that
# predates hook registration). Removing an unknown ID from a set is a no-op;
# decrementing a counter drives it negative and the badge never clears.
#
# Entries are "id:epoch" and expire, because SubagentStop is not guaranteed: a
# harness killed while children run strands ids with nothing to remove them.
# Self-healing matters more than precision; dropping a live subagent early only
# means the badge reads "done" slightly early.
# ---------------------------------------------------------------------------
SUB_TTL=1800   # 30 min

prune_agents() {   # $1=pane, $2=id to drop (optional), $3=id to add (optional)
    local pane="$1" drop="$2" add="$3" now out="" e id ts
    now=$(date +%s)
    for e in $(tmux show -p -t "$pane" -qv @cc_pane_agents 2>/dev/null); do
        id="${e%%:*}"; ts="${e##*:}"
        [[ "$id" == "$drop" ]] && continue
        [[ "$id" == "$add"  ]] && continue          # re-add below, keeps it idempotent
        [[ "$ts" =~ ^[0-9]+$ ]] || continue         # malformed, drop
        (( now - ts > SUB_TTL )) && continue        # expired
        out+="${out:+ }$e"
    done
    [[ -n "$add" ]] && out+="${out:+ }${add}:${now}"
    if [[ -n "$out" ]]; then
        tmux set -p -t "$pane" @cc_pane_agents "$out" 2>/dev/null
    else
        tmux set -pu -t "$pane" @cc_pane_agents 2>/dev/null
    fi
}

if [[ "$state" == sub-start || "$state" == sub-stop ]]; then
    aid=$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)
    if [[ -n "$aid" ]]; then
        if [[ "$state" == sub-start ]]; then
            prune_agents "$pane" "" "$aid"
        else
            prune_agents "$pane" "$aid" ""
        fi
    fi
fi

# Resolve the window owning this pane. If the pane is gone (race with a closing
# window) every subsequent tmux call would fail, so bail quietly.
win=$(tmux display -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null) || exit 0
[[ -n "$win" ]] || exit 0

# Tool events also fire for subagents and background tasks after the parent
# turn has stopped. Those carry agent_id (parent-originated events do not) and
# say nothing about the parent, so ignore them; otherwise a finished pane would
# flip back to working and never settle.
if [[ "$state" == tool ]]; then
    if [[ -n "$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)" ]]; then
        exit 0
    fi
fi

if [[ "$state" == tool ]]; then
    # A parent tool call means the agent is working, whatever the prior state:
    # neither harness fires a hook when permission is granted, so this is what
    # clears `needs`.
    case "$(tmux display -p -t "$pane" '#{pane_current_command}' 2>/dev/null)" in
        *codex*) state=thinking ;;
        *)       state=working ;;
    esac
fi

# Compaction is an interlude, not a state change: stash the prior state on the
# way in and restore it on the way out, so a compaction after a finished turn
# doesn't flip a settled pane back to working.
if [[ "$state" == busy ]]; then
    prev=$(tmux show -p -t "$pane" -qv @cc_pane_state 2>/dev/null)
    [[ -n "$prev" && "$prev" != "busy" ]] \
        && tmux set -p -t "$pane" @cc_pane_prev "$prev" 2>/dev/null
fi

if [[ "$state" == uncompact ]]; then
    state=$(tmux show -p -t "$pane" -qv @cc_pane_prev 2>/dev/null)
    tmux set -pu -t "$pane" @cc_pane_prev 2>/dev/null
    # No stash (compaction began before tracking): assume settled, because a
    # wrong "working" is never cleared.
    [[ -n "$state" ]] || state=idle
fi

# SessionStart re-fires after a compaction (Codex: source=compact; Claude's
# matcher excludes it). Only a genuinely new session resets state.
if [[ "$state" == session-start ]]; then
    src=$(printf '%s' "$payload" \
          | jq -r '.source // .session_start_reason // empty' 2>/dev/null)
    case "$src" in
        compact) exit 0 ;;   # mid-turn housekeeping, not a new session
        rewind)  state="done" ;;
        *)       state=idle ;;
    esac
fi

# SessionEnd: clear this pane explicitly. The agent is still the pane's running
# command when the hook fires, so the prune in the loop below would miss it.
if [[ "$state" == gone ]]; then
    tmux set -pu -t "$pane" @cc_pane_state 2>/dev/null
    tmux set -pu -t "$pane" @cc_pane_since 2>/dev/null
    tmux set -pu -t "$pane" @cc_pane_agents 2>/dev/null
fi

# Window focused: demote every done pane in it, not just the focused one, which
# in a split may be a plain shell.
if [[ "$state" == "seen" ]]; then
    w=$(tmux display -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null)
    while IFS= read -r sp; do
        [[ -n "$sp" ]] || continue
        [[ "$(tmux show -p -t "$sp" -qv @cc_pane_state 2>/dev/null)" == "done" ]] \
            && tmux set -p -t "$sp" @cc_pane_state idle 2>/dev/null
    done < <(tmux list-panes -t "$w" -F '#{pane_id}' 2>/dev/null)
fi

# A turn that finishes while you are already looking at the pane has, by
# definition, been seen -- record it as idle rather than done. pane-focus-in only
# fires on a focus *transition*, so without this a pane you were already watching
# keeps its ● until you leave the window and come back.
if [[ "$state" == "done" ]]; then
    visible=$(tmux display -p -t "$pane" \
        '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}' 2>/dev/null)
    [[ "$visible" == "1" ]] && state=idle
fi

if [[ "$state" != reap && "$state" != gone && "$state" != seen \
      && "$state" != sub-start && "$state" != sub-stop ]]; then
    tmux set -p -t "$pane" @cc_pane_state "$state"  2>/dev/null
    tmux set -p -t "$pane" @cc_pane_since "$(date +%s)" 2>/dev/null
fi

# The window state is the highest-severity pane state, not the last writer.
rank() {
    case "$1" in
        needs)   echo 6 ;;
        done)    echo 5 ;;
        waiting) echo 4 ;;   # finished, but background subagents still running
        busy)     echo 3 ;;   # compacting: below done, above plain working
        working)  echo 2 ;;
        thinking) echo 2 ;;   # same urgency as working, different agent
        idle)    echo 1 ;;
        *)       echo 0 ;;
    esac
}

# Per-state glyph + colour. Kept here rather than in tmux.conf because a format
# string cannot loop over panes -- the multi-pane badge has to be pre-rendered.
#
# Two tiers, and the split is deliberate:
#
#   ACTIONABLE (done, waiting, needs) -- agent-neutral shape and colour: the
#       response is the same whichever harness produced it. Shape and colour
#       both encode state, so these survive a colour-blind reading.
#
#   AMBIENT (active, idle, compacting) -- agent-specific: nothing is asked of
#       you, so show what is running where. Tinted when live, dimmed when idle.
#
# $1 = state, $2 = agent glyph, $3 = agent colour.
glyph() {
    local g="${2:-✻}" c="${3:-#D97757}"
    case "$1" in
        # -- actionable: neutral --
        needs)   printf '#[fg=red]◆#[default]' ;;
        done)    printf '#[fg=green]●#[default]' ;;
        # Finished with subagents still running: the agent glyph in yellow
        # rather than new vocabulary, since mistaking it for done is cheap.
        waiting) printf '#[fg=yellow]%s#[default]' "$g" ;;
        # -- ambient: agent-specific --
        working|thinking) printf '#[fg=%s]%s#[default]' "$c" "$g" ;;
        idle)             printf '#[fg=brightblack]%s#[default]' "$g" ;;
        busy)             printf '#[fg=%s]◐#[default]' "$c" ;;
    esac
}

# Glyph + colour for a pane's agent: Claude ✻ in Anthropic clay, Codex ✾ in the
# blue from the codex binary. Solid shapes only; hollow ones smear when bold.
agent_style() {
    case "$1" in
        *codex*) printf '✾ #3b82f6' ;;
        *)       printf '✻ #D97757' ;;
    esac
}

best=""
best_rank=0
badge=""
n=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    p="${line%% *}"
    cmd="${line#* }"
    ps_state=$(tmux show -p -t "$p" -qv @cc_pane_state 2>/dev/null)
    [[ -n "$ps_state" ]] || continue

    # Drop state for panes no longer running an agent. Quitting leaves the pane
    # alive as a shell, so pane-exited never fires; checking the live command
    # covers clean quit, crash, and kill without relying on SessionEnd.
    if [[ " $AGENT_CMDS " != *" $cmd "* ]]; then
        tmux set -pu -t "$p" @cc_pane_state 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_since 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_agents 2>/dev/null
        continue
    fi

    # `waiting` is derived, not stored, so the final SubagentStop reverts it to
    # `done` on the next recompute. It is Claude-only: Codex's SubagentStop does
    # not fire reliably. Codex subagent events are still recorded.
    if [[ "$cmd" != *codex* ]] \
       && [[ "$ps_state" == "done" || "$ps_state" == "idle" ]]; then
        # Prune before testing, so expired ids cannot pin a pane to `waiting`
        # without a fresh subagent event ever arriving to clean them up.
        prune_agents "$p" "" ""
        [[ -n "$(tmux show -p -t "$p" -qv @cc_pane_agents 2>/dev/null)" ]] && ps_state=waiting
    fi

    r=$(rank "$ps_state")
    if (( r > best_rank )); then
        best_rank=$r
        best="$ps_state"
    fi
    # One glyph per agent pane, in pane order. The separator is a plain space:
    # ✻ overhangs its cell, and a coloured separator would repaint and clip it.
    [[ -n "$badge" ]] && badge+=' '
    # shellcheck disable=SC2046
    badge+="$(glyph "$ps_state" $(agent_style "$cmd"))"
    (( n++ ))
done < <(tmux list-panes -t "$win" -F '#{pane_id} #{pane_current_command}' 2>/dev/null)

if [[ -n "$best" ]]; then
    # @cc_win_state stays the aggregate: the pane-focus-in hook keys off it, and
    # it is the single value to test for "does this window want attention".
    tmux set -w -t "$win" @cc_win_state "$best" 2>/dev/null
    tmux set -w -t "$win" @cc_win_badge "$badge " 2>/dev/null
else
    tmux set -wu -t "$win" @cc_win_state 2>/dev/null
    tmux set -wu -t "$win" @cc_win_badge 2>/dev/null
fi

# status-interval is 15s; without this the badge would lag by up to that long.
tmux refresh-client -S 2>/dev/null

exit 0
