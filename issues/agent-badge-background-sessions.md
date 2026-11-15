# Agent badge: no badge for a background Claude session viewed with `claude attach`

**Status:** implemented on branch `agent-badge-bg-viewers` (agent-badge 1.2.0,
2026-11-15), with seeding; see [Implementation](#implementation-2026-11-15).
Tested automatically and with one live background session; the manual checks
on the operator's own tmux are still open.

**Problem:** a window running `claude attach ID` on a background session (`claude --bg`) shows
no badge. The badge hooks run in the session's own process, which the background daemon
started (`claude bg-pty-host`, under `claude daemon run`). That process has no `TMUX` or `TMUX_PANE`. The attach client
does have the pane, but it is only a viewer: the hooks never run there. So the badge is
skipped at both of its checks:

- `plugins/agent-badge-claude/hooks/register.ts`: `send` returns when `TMUX_PANE` is empty,
  and sends nothing unless the session is interactive (`e.isInteractive`).
- `scripts/agent-status.sh`: exits when `TMUX` is empty.

Seen 2026-11-09: in a desk's tmux session, the pane running its lead had
`@cc_pane_state`, while `%91`, running `claude attach af5f302a`, had no `@cc_` options at all.

## Proposed fix

- In the mod, when `TMUX_PANE` is empty, find the pane whose process is
  `claude attach <this session's id>` (`tmux list-panes -a -F '#{pane_id} #{pane_pid}'`, then
  each pane's command line) and pass it to `agent-status.sh STATE PANE`.
- Let background sessions through the interactive-only check when an attached pane is found.
- In `agent-status.sh`, accept an explicit pane without `TMUX` set (the default socket).
- With no attached pane, do nothing, as now. If the viewer detaches or a second one attaches,
  look the pane up again at each event rather than caching it.
- Test: a background session attached in a window shows working, done and needs. Detached, it
  writes nothing.

## Research, 2026-11-14

Claude Code 2.1.325. **O** means observed in a probe on this machine; **D**
means documented, including the mod API types shipped with the build; **I**
means inferred. The probes used throwaway `claude --bg` sessions with no
prompt, a temporary mod loaded with `--plugin-dir`, and an isolated
`tmux -L` server. Each session was stopped and removed afterwards.

### What the harness actually does

- **The session process** (**O**). The process tree is `claude daemon run` →
  `claude bg-pty-host … 200 50 -- <versioned binary> --session-id …`. The
  environment has `CLAUDE_CODE_SESSION_KIND=bg`, `CLAUDE_JOB_DIR`,
  `CLAUDE_CODE_SESSION_NAME` and no `TMUX` or `TMUX_PANE`, even when `--bg` is
  run inside tmux. `~/.claude/sessions/<pid>.json` has `"kind":"bg"` and a
  `jobId` (the short id), and no `tmux` field, so `agent-reconcile.sh` skips it.
  The daemon keeps the environment of the shell that first started it, not that
  of later `--bg` callers.
- **Mods run in background sessions, and they count as interactive** (**O**).
  `session.start` arrived with `isInteractive: true` and `surface: "terminal"`.
  The interactive check in `register.ts` does not block the badge; only the
  empty `TMUX_PANE` does. The "let background sessions through" step in the
  proposal above is unnecessary.
- **`claude attach` is a thin client** (**O**). It connects to the daemon's
  `control.sock`, and the daemon relays the session's PTY. It writes no
  session file, and nothing on disk records which terminal is viewing a
  session.
- **No mod event marks a terminal attach** (**O**, **D**).
  `session.attach` and `session.detach` exist, but they are for remote
  surfaces: "a remote client joins the session's roster … (ui_attach)". A
  terminal `claude attach` fired neither, and `$.session.surfaces()` stayed
  `["terminal"]`.
- **The attach argument is not always an id** (**O**, **D**: 2.1.290 "Added
  `claude attach <name>`"). `claude attach badge` attached `badge-probe2`. In
  a shell pane the client is the shell's foreground child, `claude attach
  badge` with `ps` state `Sl+`, and `pane_current_command` is `claude`, so the
  existing prune keeps the pane.
- **Ctrl+Z ends the client** (**O**). The pane returns to the shell with no
  stopped job, so the next recompute prunes the pane's state, as for a quit.
- **Refreshing without a client context fails** (**O**). Without a client
  context `tmux refresh-client -S` fails with "no current client", so a write
  from the background process would wait for `status-interval` (15 s).
- **Not observable: the agent view** (**I**). Opening a session from
  `claude agents` leaves the process's arguments as `claude agents`, and
  nothing ties that pane to the session it shows.

### Revised fix

1. **`register.ts`.** When `TMUX_PANE` is empty and `CLAUDE_CODE_SESSION_KIND`
   is `bg`, run `agent-status.sh STATE` with an empty pane, and set
   `AGENT_BADGE_SESSION=<$.session.id()>` in `process.run`'s `env`. Keep the
   interactive check.
2. **New `plugins/shared/scripts/agent-viewers.sh <session-id>`**, copied out by
   `sync-shared.sh`. It prints the panes viewing that session on the default
   server, `${TMUX_TMPDIR:-/tmp}/tmux-$UID/default`:
   - Read this session's `jobId` and current `name` from the
     `~/.claude/sessions/*.json` whose `sessionId` matches. The name changes
     with `/rename`, so it is read at every event, never cached. Read every
     other live session's name as well.
   - Run one `tmux -S <socket> list-panes -a -F '#{pane_id} #{pane_tty}'` and
     one `ps -e -o tty=,stat=,args=`. Keep the foreground processes (`+`)
     whose `argv[0]` basename is `claude` and whose next argument is `attach`.
   - A pane matches when the argument equals the `jobId`, is a prefix of the
     session id, or is a case-insensitive part of this session's name and of
     no other live session's name. An ambiguous name matches nothing, because
     a wrong badge is worse than none.
3. **`agent-status.sh`.** When `pane` is empty and `AGENT_BADGE_SESSION` is
   set:
   - Read the payload once.
   - For each pane `agent-viewers.sh` prints, run itself again with
     `TMUX=<socket>,0,0` and that pane, giving it the payload on stdin.
   - Exit when no pane is found; this keeps today's behavior.

   Make the closing refresh work without a client context, by refreshing each
   client from `tmux list-clients -F '#{client_name}'` when `refresh-client -S`
   fails.
4. **Optional seeding.** Nothing fires when a viewer attaches, so the pane
   stays unbadged until the session's next event. `agent-reconcile.sh`, which
   runs on `pane-focus-in`, could seed a pane that has no state and runs
   `claude attach` by resolving it the same way. It would map the session
   file's `busy` to `working` and `idle` to `idle`, never `needs`. That is the
   reconciler's first non-demotion write, so it is a choice to make, not a
   default.

Known gaps to document in the plugin README:

- A session viewed from the agent view.
- A tmux server on a non-default socket.
- A name argument that matches more than one session.

Two viewers both get the badge, which is intended.

### Tests

Extend `tests/agent-badge.sh`. It already runs a private `tmux -L` server
with a `TMUX_TMPDIR` under its temporary root. Add:

- A fake `claude` on `PATH` (a script that sleeps, run as `claude attach <arg>`)
  in a test pane, and a fixture `sessions/<pid>.json` under a temporary HOME
  with `"kind":"bg"`.
- `AGENT_BADGE_SESSION=<id> agent-status.sh working`, with `TMUX` and
  `TMUX_PANE` unset. It must badge the pane for the short id, the full id, a
  unique part of the name and the full name. An ambiguous part of the name, a
  pane whose foreground is a shell, and no matching pane must write nothing.
- `done` on a visible pane demotes to `idle`, as it does today. After the fake
  client exits, the next recompute prunes the pane.
- `bash -n`, ShellCheck, and `plugins/sync-shared.sh --check`.

The mod change is a few lines, so cover it in `plugins/agent-badge-claude/tests/agent-badge.test.ts`:
`TMUX_PANE` empty with kind `bg` must call the script with the session id in
`env`, and empty with any other kind must make no call.

Manual check, in tmux over SSH:

1. Run `claude --bg -n x`.
2. In another window, run `claude attach x`. The badge shows working, then done
   after a prompt; `needs` shows on a permission prompt.
3. Press Ctrl+Z. The badge clears.
4. Attach from two windows. Both are badged.

## Seeding experiments, 2026-11-15

A dedicated pass tried five ways to badge a viewer pane before the session's
next event, on Claude Code 2.1.325 and tmux 3.8. **O** = observed; the
machine was heavily loaded, so the latencies are upper bounds.

| Approach | Result |
| --- | --- |
| Seed from the session file on any pane's focus | Works (**O**). Badged 74–349 ms after focus moved. The steady-state cost is one `list-panes` call (31 ms, against 41 ms before). Fails as a missing badge, never a wrong one. |
| `pane-title-changed` | Works for the agent view (**O**): it titles the pane with the open session's name, badged in 72–174 ms and cleared in 135 ms back on the list. It also works for `claude attach` while the session is busy (**O**, live run below): Claude Code retitles the terminal (`✳ <name>`), and the attach relays it. An idle attached session leaves the title alone. |
| The mod re-announcing on terminal resize | Rejected (**O**). It misses a re-attach at the same width, brought back a `done` that had already been seen, and two viewers flap the reported size. |
| OSC 133;C plus `pane-command-started`, or a shell wrapper for `claude attach` | Works (about 0.5 s), but needs shell help, so it is optional and dotfiles-only. Not built. |
| Other tmux hooks, a mod timer | `window-renamed` does not fire with path-named windows; a timer is polling, which the README rules out. |

The session file's `waiting` is trustworthy for seeding `needs` (**O**): it
appears about 170 ms before the mod's permission event and clears on Esc. The
job file's `needs` is free text and is not used. `claude attach` itself refuses
an ambiguous name ("2 sessions match"), so a running client always had a unique
argument.

## Implementation, 2026-11-15

Agent-badge 1.2.0 (Claude) and 1.2.0+codex (the shared scripts):

- `hooks/register.ts`: with no `TMUX_PANE` and `CLAUDE_CODE_SESSION_KIND=bg`,
  it calls `agent-status.sh STATE ''` with `AGENT_BADGE_SESSION=<session id>`.
  The interactive check stays, because background sessions are interactive.
- `scripts/agent-viewers.sh` (new): `panes <session>` and `session <pane>`.
  It resolves attach arguments by short id, session-id prefix, exact name, or a
  unique part of a name, and the agent view by its exact pane title. It uses one
  `list-panes` and one `ps`; argv is split without globbing, and a name with
  spaces is kept whole.
- `scripts/agent-status.sh`: the background route.
  - It finds the viewers on the default socket and wires the server, since a
    server running only background sessions was never wired. This is a gap the
    live run found.
  - It tags each viewer pane with `@cc_pane_session` and `@cc_pane_view`, then
    re-runs itself per pane with `TMUX` set to that socket.
  - The closing refresh falls back to refreshing each client, because there is
    no client context.
- `scripts/agent-reconcile.sh`: seeding, the reconciler's one promoting write.
  It only touches panes the hooks have not written, and maps busy → working,
  idle → idle, waiting → needs, never done. Demotion now also reaches viewer
  panes through their session tag.
- `agent-badge.tmux` (wiring version 3): adds `pane-title-changed` (seed) and
  `pane-shell-prompt` (reap), both guarded by `if -F`, so no process starts
  unless the pane qualifies. Each hook is wired only if this tmux accepts it.

Evidence:

- `tests/agent-badge.sh` drives a private server named `default`, where perl
  stands in for each viewer. It covers:
  - attach by id, by any-case part of the name, and through the agent view;
  - ambiguity, and a pane that views nothing;
  - session tags and the window badge, a session ending, and seeding of
    waiting → needs;
  - busy demoting a seeded `needs`, and no overwrite of a hook's `done`;
  - the agent view switching sessions and returning to its list;
  - a dead session.

  Breaking the lookup makes it fail.
- The mod tests add the background route, and a pane taking priority over it
  (9 pass).
- Live run with Claude Code 2.1.325: a real `claude --bg` session loaded the
  branch plugin through `--plugin-dir`, under a daemon whose `TMUX_TMPDIR`
  pointed at a private server. `claude attach` in that server went working →
  done ●. After Ctrl+Z out of a busy turn and a re-attach, the pane was seeded
  `working` within 2 s through the title hook, then went to done when the turn
  ended. The session, server and daemon were cleaned up.

Known gaps: a viewer on a non-default tmux socket; an agent-view title for an
unnamed session (not tested); zsh, and tmux before 3.8 (hooks are
feature-detected, not tested).

Still to check by hand on the operator's tmux, over SSH:

1. Run `claude --bg -n x`, then `claude attach x` in a window; the badge follows
   the turns.
2. Open `x` from `claude agents`; the badge appears, and clears on the list.
3. Ctrl+Z out of the attach clears the badge.
4. Re-attach to a busy session; the badge appears within a few seconds.
5. Two viewers are both badged.

Pre-existing, not this change: `tests/agent-badge.sh` ends with
`claude plugin validate --strict`. On 2.1.325 that fails on `main` as well,
with TypeScript strictness warnings, `LICENSE_MISSING` and `ICON_MISSING`.
Every check before it passes.
