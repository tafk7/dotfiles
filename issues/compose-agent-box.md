# Compose joined to an agent's prompt box

**Status:** in testing (2026-10-27). Built for Claude as step 4.3 of the
[plan](scrollback-copy-compose-plan.md) (commit `cc9c58f`). On 2026-10-27 it
was driven against the real agents (Claude 2.1.311, Codex 0.164.0, OpenCode
2.1.4) in a private tmux server, four bugs were fixed (below), and it was
extended to Codex and OpenCode. Follows
[scrollback, copy, and compose](scrollback-copy-compose.md) §5.

## What it does

While the compose pane is open, the prompt lives there; otherwise it lives in
the agent's prompt box.

| Key | Effect |
|---|---|
| The agent's editor key (Claude Ctrl+G, Codex Ctrl+E, OpenCode Ctrl+X E), or Alt+V | The box text moves to the end of the compose draft, the box empties, and the compose pane opens or takes focus with the cursor after the pulled text. The agent stays live above it |
| Ctrl+S in compose | Sends and keeps the pane open (unchanged) |
| `:q`, `:wq`, `ZZ` in compose | nvim quits at once, and the draft goes back into the box, exactly as written, followed by anything typed into the box meanwhile; the draft empties. If the agent doesn't take it within 3 s (a dialog or its transcript view has the key), the draft stays in the draft and tmux says so |
| `:cq` in compose | The box is left alone; the draft is kept for next time |
| Ctrl+Shift+G in Claude, Codex or OpenCode | The prompt in nvim with the prose profile, in the agent's place |

## How

Each agent runs `$VISUAL` on a temporary `.md` file holding the box, as its
direct child, and takes the file back on exit 0:

| Agent | Key | File | An empty file |
|---|---|---|---|
| Claude 2.1.311 | Ctrl+G (`chat:externalEditor`) | `$TMPDIR/claude-prompt-UUID.md` | clears the box |
| Codex 0.164.0 | Ctrl+E here (`open_external_editor`, set by `configs/codex.defaults.toml`) | `~/.codex/editor/.tmpXXXXXX.md` | clears the box; trailing whitespace is trimmed |
| OpenCode 2.1.4 | Ctrl+X E (`prompt.editor`) | `$TMPDIR/EPOCH_MS.md` | leaves the box as it was; a lone newline clears it |

The agents blank or suspend their screen while the editor runs, so the editor
can't be the compose split itself. Instead `$VISUAL` is `bin/compose-editor`
(`shell/env.sh`), which, run by one of these agents in tmux on its prompt-box
file, calls `tmux-compose editor` and returns at once:

- no request: pull the box into the draft and open or focus the pane;
- `@compose-editor push` (asked by `tmux-compose return` when the compose
  nvim quits): the box becomes the draft's text, and the draft empties;
- `@compose-editor fullscreen` (asked by Ctrl+Shift+G): nvim in the agent's
  place.

A request is made one way: set the pane option, press the agent's key, and
wait for `editor` to clear the option. One the agent doesn't take in time is
withdrawn, so that it can't apply to a later key press. Every other file gets
`$EDITOR`: git's, and the agents' own other uses of `$VISUAL`, such as
Claude's transcript (`v` in its Ctrl+O view), plans, and `/memory`.

## Testing against the real agents (2026-10-27)

Fixed:

1. **Quitting compose while Claude showed a dialog** (a question, a permission
   prompt) or its transcript view: nvim froze for 3 s, then the draft was
   pasted into the dialog, which ignored it, and the draft was emptied; the
   text survived only in `history.md`. The same freeze and paste followed
   whenever Claude took longer than 3 s. Now nvim quits at once, the tmux
   server waits for the agent, and a draft it doesn't take stays in the draft,
   with a message.
2. **Claude's other uses of `$VISUAL`.** Its transcript view's `v` ran
   `compose-editor` on the transcript, which was taken for the prompt box and
   moved, all 325 lines, into the draft; a plan edited in the editor or
   `/memory` would have gone the same way. `compose-editor` now joins only the
   prompt-box file.
3. **A pull into an open compose pane took 1.1 s before focus moved,** and
   keys typed in that second went into the agent's box. The nvim client that
   tells the compose nvim to reread the draft waited on terminal queries on the
   agent's tty; headless, with stdin from `/dev/null`, it takes 35 ms. The
   cursor now moves to the end of the pulled text; it stayed where it was,
   often on line 1.
4. **The nvim socket lived beside the draft.** Under a long `XDG_STATE_HOME`
   its path passed the 107-byte limit and nvim exited at once, so the pane
   flashed and closed. It is under `$XDG_RUNTIME_DIR` now, recorded as
   `@compose_socket`.

Checked and fine: Claude runs its editor mid-turn (this was the open busy
case) and takes Ctrl+G in about 0.2 s; Codex takes Ctrl+E in about 0.2 s and
OpenCode Ctrl+X E in about 0.3 s. A collapsed paste (`[Pasted text #1 +45
lines]`) reaches the draft expanded and goes back expanded. Keys typed before
the compose nvim has started land in order. Ctrl+Shift+G round trips in
Claude and OpenCode, and Ctrl+S sends to Codex and OpenCode.

## Using it

- Open new shells, then start the agents in them: an agent started before
  keeps its old `VISUAL` and gets the plain compose pane (no pull; the draft
  stays parked on quit).
- Ctrl+Shift+G needs the current `configs/wezterm.lua` (or the Windows
  Terminal keybindings), which send it as `\e[27;6;71~`.
- Codex's key is fixed at Ctrl+E in `bin/tmux-compose` (`editor_key`), as
  `configs/codex.defaults.toml` binds it. If it is rebound in Codex
  (`/keymap`), Ctrl+E there no longer pulls, Alt+V opens the pane after a
  second without the box, and a returned draft is kept.

## Open questions and checks

- **`:q` and `:wq` are the same.** The draft autosaves, so there is no way to
  quit without returning it except `:cq`. Decide whether that is right in use.
- **Images.** An attached image shows as `[Image #1]` in Claude's box; the
  placeholder moves through the draft as text. Untested whether Claude keeps
  the image when the text comes back.
- **No fullscreen key in Codex.** Its Ctrl+Shift+G is a permission-mode key
  (previous mode), which reaches it as Ctrl+G (next mode) through tmux 3.4.
- **Ctrl+Shift+G outside these agents** reaches the program as plain Ctrl+G,
  because tmux 3.4 can't send the extended key to a pane that hasn't asked
  for it.

## Tests

`tests/tmux-compose-agents.sh`, with a stub that keeps a prompt box and runs
`$VISUAL` as each agent does (its key, its file name, its handling of an empty
file):

- in Claude: pull into a new and an open pane, Alt+V, return with and without
  text typed meanwhile, Ctrl+Shift+G;
- Claude's transcript, a plan, and `CLAUDE.md`, Codex's other files, and
  files outside an agent going to `$EDITOR` with the draft untouched;
- a Claude that doesn't run its editor: `return` doesn't wait, the request is
  withdrawn after 3 s with a message, nothing is pasted, and the draft is
  kept; Alt+V still opens the pane;
- a Claude without `compose-editor`, and Ctrl+Shift+G outside the agents;
- Codex and OpenCode: pull, Alt+V, return, and Ctrl+Shift+G;
- with real nvim: `:q`, `:cq`, and a pull into an open pane, typing on after
  the pulled text.

The tests fail on the code before these fixes.
