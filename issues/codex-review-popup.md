# Keyboard review for Codex panes

**Status:** done, in a different shape, as phase 5 of [scrollback, copy, and
compose](scrollback-copy-compose.md) (§3.3): review renders the session file
(`bin/codex-transcript`) into a copy-mode review pane, not an nvim popup, and
the exact link the catch below asked for turned out to be the pane title. With
`thread-id` in `tui.terminal_title`, Codex 0.164 writes the thread's id there,
cut to 29 characters, which still name one rollout file (spec §1.2.22). The
newest-session-in-this-directory heuristic remains as the fallback, and says so
in its first line. Kept for the record below.

## Problem

Review (ScrollLock, `C-a v`) gives shell and Claude panes a tmux copy-mode
view, and OpenCode panes its exported session in a read-only nvim popup. Codex
panes only get `F3`, Codex's own transcript search. Fullscreen Codex has no
transcript pager and no keyboard selection: `Ctrl+T` only expands output in
place, and copying is a mouse drag or `Ctrl+O` (last reply). There is no way to
move around a Codex transcript with the keyboard, select part of it, and copy
it.

## Idea

Review in a Codex pane renders Codex's session file into Markdown and opens it
in the same review popup OpenCode uses (`bin/tmux-review`'s `popup`): full
keyboard motion, visual selection, `/` search, and yanks that reach the
clipboard through tmux.

- Session files: `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl` (default
  `~/.codex`). The first record is `session_meta` with `cwd`; the transcript is
  in `response_item` records: `message` (role `user` / `assistant`, text
  content), `custom_tool_call` and `custom_tool_call_output`, `reasoning`.
- Rendering: user and assistant messages as headed sections; tool calls and
  their output as fenced blocks; reasoning left out.
- `F3` stays available inside Codex for its own search.

## The catch: which session

A pane can't be tied to its session file directly. Codex 0.162 runs its agent
in a background app-server daemon that writes the session file; the TUI in the
pane has no handle on it, and its command line names no session unless it was
started with `resume`. The fallback is the most recently written session file
whose `cwd` is the pane's directory, which picks the wrong session when two
Codex panes share a directory.

Before building, look for an exact link: a session or thread ID in the TUI's
environment, its open sockets, the daemon's state files, or
`~/.codex/session_index.jsonl`; or a Codex keybinding or slash command that
writes the transcript out (as OpenCode's export does). Failing that, ship the
heuristic and say in the popup's first line which session it shows.

## Tests

A Codex stub in a directory with two session files (an older one and a newer
one for the same `cwd`, and one for another directory): review opens the
newer same-directory session rendered as Markdown, mode 600, and the
temporary file is gone afterwards.
