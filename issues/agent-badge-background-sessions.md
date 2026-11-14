# Agent badge: no badge for a background Claude session viewed with `claude attach`

**Status:** open (2026-11-09).

**Problem:** a window running `claude attach ID` on a background session (`claude --bg`) shows
no badge. The badge hooks run in the session's own process, which the background daemon
started (`claude bg-spare`). That process has no `TMUX` or `TMUX_PANE`. The attach client
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
