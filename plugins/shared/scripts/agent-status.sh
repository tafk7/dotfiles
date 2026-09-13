#!/bin/bash
# Coding-agent -> tmux window badge  (Claude Code + Codex CLI)
#
# Writes the calling pane's Claude state into tmux user options, aggregates the
# per-pane states up to a window-level option, and forces a status redraw.
# The badge itself is rendered by window-status-format in ~/.tmux.conf.
#
# Usage: agent-status.sh <state> [pane]  state = working|done|needs|idle|busy|
#                                                thinking|tool|reap|gone
#
# Wired from THREE places, all of which pass state as argv[1]:
#   hooks/hooks.json          (Claude Code, via the plugin manifest)
#   ~/.codex/config.toml      [[hooks.*]]      (Codex CLI, via codex/install.sh --
#                             Codex's own plugin hooks are feature-gated and do
#                             not execute as of 0.150.1, so it cannot use the
#                             plugin manifest yet)
#   the tmux server           pane-focus-in / pane-exited, installed by
#                             ../agent-badge.tmux
#
# Agent-agnostic by design: the only agent-specific thing here is AGENT_CMDS,
# the list of process names that count as a live agent pane.
#
# The optional [pane] argument exists because the two callers differ: a Claude
# Code hook inherits $TMUX_PANE from the Claude process, but a tmux-spawned hook
# gets $TMUX only -- no $TMUX_PANE -- so tmux.conf passes #{pane_id} explicitly.
#
# Contract: never block Claude, never write to stdout (hook stdout can be
# interpreted), always exit 0.

# Process names that count as an agent pane. A pane running anything else has
# its state pruned -- quitting an agent drops back to a shell without killing the
# pane, so nothing else would ever clear the stale glyph.
AGENT_CMDS="claude codex"

state="$1"
pane="${2:-$TMUX_PANE}"

# Not in tmux (plain terminal, SSH without tmux, CI) -> nothing to do.
[[ -n "$TMUX" && -n "$pane" ]] || exit 0

if ! command -v jq >/dev/null 2>&1; then
    if [[ "$state" == session-start ]]; then
        printf 'agent-badge: jq is required on PATH; see the plugin README.\n' >&2
    fi
    exit 0
fi

# Self-heal the tmux wiring. The badge placeholder living in
# window-status-format is the one piece of state that gets destroyed routinely:
# `source-file ~/.tmux.conf` (bound to prefix+r) resets the option to whatever
# the file says, stripping it. It is also simply absent on a machine where the
# plugin is installed but no dotfiles are.
#
# Checked only on the two low-frequency events, and content-first, so the steady
# state costs a single `show -gv`. agent-badge.tmux is itself idempotent and
# separately guarded; this just decides whether to bother calling it.
case "$state" in
    seen|session-start)
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

# Only the subagent events need the payload (for agent_id); every other caller's
# stdin is irrelevant. Read it *only* when required, and always under a timeout:
# an unconditional `cat` blocks forever if stdin is neither a tty nor closed,
# which would leave a stuck process behind for every hook invocation.
payload=""
if [[ "$state" == sub-start || "$state" == sub-stop || "$state" == tool \
   || "$state" == session-start ]] && [[ ! -t 0 ]]; then
    payload=$(timeout 2 cat 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# Background subagents
#
# SubagentStop fires even for agents that outlive the parent turn (verified: a
# Stop at 10:58:44 was followed by its SubagentStop at 11:02:36), so the parent
# pane can legitimately be "done" while work is still in flight.
#
# Track the live agent IDs as a set rather than a counter. The events carry no
# ordering guarantee and a Stop can arrive for an ID we never saw -- observed
# live when an agent predated the hook being registered. Removing an unknown ID
# from a set is a harmless no-op; decrementing a counter for one drives it
# negative and the badge never clears.
# ---------------------------------------------------------------------------
# Entries are stored as "id:epoch" and expire. SubagentStop is not guaranteed:
# a harness killed or restarted while children run leaves ids in the set with
# nothing to remove them, and the pane then shows "waiting" forever. Observed
# live -- two Codex ids stranded 26 minutes. Expiry makes the set self-healing,
# which matters more than precision here: the cost of dropping a real subagent
# early is a badge that reads "done" while something finishes quietly.
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

# PostToolUse fires on every tool call, including ones a *subagent* or a
# background task makes after the main turn already emitted Stop. Writing
# "working" unconditionally there resurrects a finished window back to ✻ and it
# never settles -- the bug where a done pane kept showing as running. So a
# tool-driven update only applies when the pane isn't already resolved.
# A tool event carrying agent_id came from a *subagent*, not the pane's own
# agent, and says nothing about what the parent is doing. Codex confirmed:
# parent-originated Pre/PostToolUse have no agent_id key; subagent ones carry
# agent_id + agent_type. Letting these through made a parent that had already
# finished look busy again.
if [[ "$state" == tool ]]; then
    if [[ -n "$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null)" ]]; then
        exit 0
    fi
fi

if [[ "$state" == tool ]]; then
    # Parent-originated tool call => this pane's own agent is actively working.
    # There is no carve-out for already-settled states any more: the only reason
    # one existed was to stop a *subagent's* tool events resurrecting a finished
    # pane, and those are now dropped above by the agent_id filter. Keeping the
    # carve-out stranded panes instead -- `needs` never cleared, because neither
    # harness fires a hook when you *grant* permission, and `busy` never cleared,
    # because PostCompact routes here too.
    case "$(tmux display -p -t "$pane" '#{pane_current_command}' 2>/dev/null)" in
        *codex*) state=thinking ;;
        *)       state=working ;;
    esac
fi

# Compaction is an interlude, not a state change: the agent is doing the same
# thing after it as before. Stash the prior state on the way in and restore it on
# the way out. PostCompact used to route through `tool`, which unconditionally
# means "active" -- so an auto-compaction that ran *after* a turn finished flipped
# a settled pane to working and nothing ever came along to clear it.
if [[ "$state" == busy ]]; then
    prev=$(tmux show -p -t "$pane" -qv @cc_pane_state 2>/dev/null)
    [[ -n "$prev" && "$prev" != "busy" ]] \
        && tmux set -p -t "$pane" @cc_pane_prev "$prev" 2>/dev/null
fi

if [[ "$state" == uncompact ]]; then
    state=$(tmux show -p -t "$pane" -qv @cc_pane_prev 2>/dev/null)
    tmux set -pu -t "$pane" @cc_pane_prev 2>/dev/null
    # No stash (compaction began before we were tracking) -> assume settled
    # rather than active. Guessing "working" is what stranded panes before.
    [[ -n "$state" ]] || state=idle
fi

# SessionStart re-fires mid-session after a compaction (Codex: source=compact;
# Claude: matcher excludes it). Treating that as a fresh session flickered an
# actively-working pane to idle. Only a genuinely new session resets state.
if [[ "$state" == session-start ]]; then
    src=$(printf '%s' "$payload" \
          | jq -r '.source // .session_start_reason // empty' 2>/dev/null)
    case "$src" in
        compact) exit 0 ;;   # mid-turn housekeeping, not a new session
        rewind)  state="done" ;;
        *)       state=idle ;;
    esac
fi

# SessionEnd: clear this pane explicitly rather than waiting for the loop's
# command check. Claude is still the running command at the instant the hook
# fires, so the "is it still claude?" prune would not catch it yet.
if [[ "$state" == gone ]]; then
    tmux set -pu -t "$pane" @cc_pane_state 2>/dev/null
    tmux set -pu -t "$pane" @cc_pane_since 2>/dev/null
    tmux set -pu -t "$pane" @cc_pane_agents 2>/dev/null
fi

# Window focused: demote *every* done pane in it, not just the focused one.
# The old tmux hook wrote idle to whichever pane had focus, so in a split,
# focusing the shell pane demoted that (stateless) pane while the agent pane
# beside it kept its ● indefinitely.
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

# Window badge = highest-severity pane state in that window. Windows here mix a
# Claude pane with a plain shell (and window 1 runs two Claudes), so the window
# must surface whichever pane is most urgent rather than the last one to write.
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
#   ACTIONABLE (done, waiting, needs) -- agent-NEUTRAL.
#       Universal shape and semantic colour. What you do about a finished or
#       blocked session is identical whichever harness produced it, so spending
#       the glyph on agent identity buys nothing and costs the "scan for green"
#       affordance. Shape AND colour both encode state here, so the two states
#       that demand action survive a colour-blind reading.
#
#   AMBIENT (active, idle, compacting) -- agent-SPECIFIC.
#       Nothing is being asked of you, so the useful information is *what is
#       running where*. Claude ✻ / Codex ✾, tinted by the agent when live and
#       dimmed when idle.
#
# $1 = state, $2 = agent glyph, $3 = agent colour.
glyph() {
    local g="${2:-✻}" c="${3:-#D97757}"
    case "$1" in
        # -- actionable: neutral --
        needs)   printf '#[fg=yellow]◆#[default]' ;;
        done)    printf '#[fg=green]●#[default]' ;;
        # Finished, but background subagents are still running. Uses the
        # AGENT's glyph in a distinct teal-green rather than a fourth neutral
        # shape: confusing this with plain done is cheap (you glance at a window
        # a moment early), so it does not warrant new vocabulary. Every adjacent
        # pair still differs in a channel -- ✻ orange->teal by colour, ✻ teal ->
        # ● green by shape.
        waiting) printf '#[fg=#10b981]%s#[default]' "$g" ;;
        # -- ambient: agent-specific --
        working|thinking) printf '#[fg=%s]%s#[default]' "$c" "$g" ;;
        idle)             printf '#[fg=brightblack]%s#[default]' "$g" ;;
        busy)             printf '#[fg=%s]◐#[default]' "$c" ;;
    esac
}

# Glyph + colour for a pane's agent. Claude ✻ (Anthropic clay), Codex ✾ (the
# blue found in the codex binary; six-petalled to echo OpenAI's six-fold mark --
# ✦ was used first and is Gemini's logo, ⬡ before that was illegible).
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

    # Drop state for panes that are no longer running Claude. Quitting Claude
    # leaves the pane alive as a shell, so pane-exited never fires and the stale
    # @cc_pane_state would keep contributing a phantom glyph forever. Checking
    # the live command here covers every exit path at once -- clean quit, crash,
    # or kill -- without needing a SessionEnd hook to fire reliably.
    if [[ " $AGENT_CMDS " != *" $cmd "* ]]; then
        tmux set -pu -t "$p" @cc_pane_state 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_since 2>/dev/null
        tmux set -pu -t "$p" @cc_pane_agents 2>/dev/null
        continue
    fi

    # Derived, not stored: a pane that has settled but still has live subagents
    # renders as `waiting`. Deriving means the final SubagentStop flips it back
    # to plain `done` on the next recompute without rewriting @cc_pane_state.
    # `waiting` is Claude-only. Codex's SubagentStop does not reliably fire -- a
    # session interrupted or restarted while children run strands ids with
    # nothing to remove them, and the pane read "waiting" for 26 minutes in
    # practice. Its subagent events are still recorded (cheap, and useful if the
    # reliability improves), they just do not drive the badge.
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
    # One glyph per agent pane, in pane order, so a split window shows e.g.
    # "● ✻ 3:Thesis" -- left pane done, right pane still working. Panes with no
    # state (plain shells) contribute nothing.
    #
    # Separator is a plain space. A dim │ was used first to make the pane
    # boundary explicit, but it added visual weight for a distinction the glyphs
    # already carry, and ✻ is drawn wider than its cell in this font -- its
    # spokes overhang into the neighbouring cell, which a coloured separator
    # then repaints, clipping the star.
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
