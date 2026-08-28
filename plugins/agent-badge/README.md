# agent-badge

Per-window tmux badges showing what every Claude Code and Codex session in your
tmux server is doing, so you can tell at a glance which window wants you.

```
 ✻ 1:Codex   ● 2:Worker 0   ✾ ✻ 4:dotfiles   ◆ 8:R1
```

The problem it solves: several windows all running an agent, several of them in
the same directory, and no way to tell which one has finished, which is blocked
on a permission prompt, and which is still thinking — short of tabbing through
all of them.

## Glyphs

Two tiers, and the split is deliberate.

**Actionable — agent-neutral.** What you do about a finished or blocked session
is identical whichever harness produced it, so spending the glyph on agent
identity buys nothing and costs the "scan for green" affordance.

| | State | Meaning |
|---|---|---|
| `◆` yellow | `needs` | Blocked on a permission decision |
| `●` green | `done` | Finished a turn, you haven't looked yet |
| `✻` teal | `waiting` | Finished, but background subagents are still running. **Claude only** — see below |

**Ambient — agent-specific.** Nothing is being asked of you, so the useful
information is *what is running where*.

| | State | Meaning |
|---|---|---|
| `✻` orange / `✾` blue | `working` / `thinking` | Actively working (Claude / Codex) |
| `✻` `✾` dim | `idle` | An agent lives here, at rest |
| `◐` agent colour | `busy` | Compacting or summarising |

One glyph per agent pane, in pane order, so a split window reads `● ✻` — left
pane done, right pane still working. Panes running a plain shell contribute
nothing.

Glyph choice is constrained by rendering. `window-status-current-style` is bold,
and thin or hollow shapes get filled in or smeared at terminal cell size — `⬡`
and `◉` were both tried and discarded. Prefer solid silhouettes. Agent colours
are literal hex rather than theme colours, because a brand colour shouldn't
shift when you switch themes.

## Install

The plugin is distributed from this repo, which doubles as a marketplace for
both harnesses. Nothing else in the dotfiles needs to be present.

**Claude Code**

```bash
claude plugin marketplace add tafk7/dotfiles     # or a local path
claude plugin install agent-badge@tafk7
```

**Codex CLI**

```bash
codex plugin marketplace add tafk7/dotfiles     # or a local path
codex plugin add agent-badge@tafk7
```

Then **run `/hooks` inside Codex once and trust them**. Codex gates hooks behind
human review, and an untrusted hook is skipped *silently* — no error, no badges,
indistinguishable from a broken install. This is the single most likely reason
the badge does not appear.

Both harnesses load the same `hooks/hooks.json`: Codex picks it up by convention
and expands `${CLAUDE_PLUGIN_ROOT}` in the commands, so one file serves both.
`UserPromptSubmit` resolves to `working` rather than Codex's `thinking`, which is
deliberate — they render identically, since the glyph and colour come from the
pane's own command.

**tmux**

Nothing required. The plugin wires the tmux server itself, from its
`SessionStart` hook, the first time it notices the badge is missing.

If you do have the dotfiles, `configs/tmux.conf` calls it explicitly instead:

```tmux
if-shell '[ -x "$HOME/dotfiles/plugins/agent-badge/agent-badge.tmux" ]' \
    'run-shell "$HOME/dotfiles/plugins/agent-badge/agent-badge.tmux wire"'
```

The badge then exists from the moment tmux starts rather than from the first
agent session, and the wiring stays greppable from the config file. Requires
tmux 3.2+ for `#{E:...}`; below that the plugin no-ops rather than printing the
placeholder across every window.

Prefer this line when you have the dotfiles, for a reason beyond taste. Plugin
caches are version-pinned (`cache/<marketplace>/<plugin>/<version>/`) and the old
directory is swept on update, so hooks the plugin wires from a cache copy point
at a path that will eventually vanish. `wire` re-points stale entries when it
next runs, but the config line sidesteps it entirely by pinning tmux to the
working tree, which is never swept. Self-wiring stays the fallback for machines
that have the plugin and nothing else.

## Uninstall

```bash
plugins/agent-badge/agent-badge.tmux unwire    # tmux hooks, formats, options
claude plugin uninstall agent-badge@tafk7
codex plugin remove agent-badge@tafk7
```

`unwire` has to be run by hand: neither harness fires a hook on plugin removal,
and without it the tmux server keeps invoking a deleted path on every pane focus
until it restarts.

## How it works

Hooks in both harnesses call `scripts/agent-status.sh <state>`, which writes the
calling pane's state to a tmux pane option, aggregates every pane in the window
to the highest-severity state, pre-renders the badge string into
`@cc_win_badge`, and forces a redraw. `window-status-format` renders it with
`#{E:@cc_win_badge}`.

The badge is pre-rendered in shell rather than assembled in the format string
because a tmux format cannot iterate over panes.

Options written, all prefixed `@cc_`: `@cc_pane_state`, `@cc_pane_since`,
`@cc_pane_agents`, `@cc_pane_prev` (pane scope); `@cc_win_state`,
`@cc_win_badge` (window scope); `@cc_badge_wired` (server scope).

### Keeping it honest

Most of the complexity here is not in setting states — it is in clearing them.
A badge stuck on "working" is worse than no badge.

- **`pane-focus-in`** demotes `done` to `idle` (you've seen it), prunes panes no
  longer running an agent, and reconciles against Claude's own session files.
- **Quitting an agent** leaves the pane alive as a shell, so `pane-exited` never
  fires. Every recompute re-checks `pane_current_command` and drops state for
  panes that are no longer an agent — which covers clean quit, crash and kill in
  one test.
- **`scripts/agent-reconcile.sh`** reads `~/.claude/sessions/<pid>.json`, which
  carries an authoritative busy/idle status and the owning pane id. When a hook
  is *missed* — an errored turn, a killed process — that file is what unsticks
  the badge. Demotion-only, and Claude-only: Codex ships no equivalent.
- **Compaction is an interlude, not a state.** `PreCompact` stashes the prior
  state and `PostCompact` restores it, so a compaction running *after* a turn
  ends doesn't flip a settled pane back to working.
- **Subagents are tracked as a set of ids, not a counter.** Events carry no
  ordering guarantee and a stop can arrive for an id never seen; removing an
  unknown id from a set is a no-op, while decrementing a counter drives it
  negative and the badge never clears. Entries expire after 30 minutes, because
  a harness killed while children run leaves ids with nothing to remove them.
- **Tool events carrying `agent_id` are ignored.** Those came from a subagent
  and say nothing about what the parent is doing; letting them through made a
  finished pane look busy again.

### Known gaps

- `waiting` is Claude-only. Codex's `SubagentStop` does not reliably fire —
  stranded ids pinned a pane to `waiting` for 26 minutes in practice.
- Codex hooks are trusted by content hash and are skipped **silently** until
  reviewed via `/hooks`. Anything that changes a command's text — including a
  plugin update moving the cache path — un-trusts them again.
- An Esc-interrupted Codex turn strands on "working" until that pane's agent does
  something else. Codex fires no `Stop` there and has no session file to
  reconcile against, and its `Interrupt` event cannot be delivered from this
  plugin: `.codex-plugin/plugin.json` declaring `hooks` silently stops *all*
  hooks loading, and putting `Interrupt` in the shared `hooks/hooks.json` makes
  Claude reject the whole file (`Hooks (0)`, validation fails). Both verified.
  Claude recovers from the equivalent on its own via the reconciler.
- Two harnesses in the *same pane* clobber each other's state. Two in the same
  *window*, in different panes, is fine and shows both glyphs.
- Badges update on hook activity or on focus, not continuously. There is no
  polling daemon, by choice.
