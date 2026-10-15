# Compose joined to Claude's prompt box

**Status:** in development and testing. Built as step 4.3 of the
[plan](scrollback-copy-compose-plan.md) (commit `cc9c58f`); the automated tests
pass and the idle case was checked against Claude 2.1.287, but it hasn't seen
daily use yet. Follows [scrollback, copy, and compose](scrollback-copy-compose.md) §5.

## What it does

While the compose pane is open, the prompt lives there; otherwise it lives in
Claude's prompt box.

| Key | Effect |
|---|---|
| Ctrl+G in Claude, or Alt+V | The box text moves to the end of the compose draft, the box empties, and the compose pane opens or takes focus. Claude stays live above it |
| Ctrl+S in compose | Sends and keeps the pane open (unchanged) |
| `:q`, `:wq`, `ZZ` in compose | The draft goes back into the box, exactly as written, followed by anything typed into the box meanwhile; the draft empties |
| `:cq` in compose | The box is left alone; the draft is kept for next time |
| Ctrl+Shift+G in Claude | The prompt in nvim with the prose profile, in Claude's place (Claude's own Ctrl+G) |

## How

Claude's Ctrl+G (`chat:externalEditor`) runs `$VISUAL` on a temporary `.md`
file holding the box, as its direct child, and takes the file back on exit 0
(an empty file clears the box; a non-zero exit keeps it). Claude blanks its
pane while the editor runs, so the editor can't be the compose split itself.
Instead `$VISUAL` is `bin/compose-editor` (`shell/env.sh`), which, run by a
`claude` process in tmux, calls `tmux-compose editor` and returns at once:

- no request: pull the box into the draft and open or focus the pane;
- `@compose-editor push:FILE` (set by `tmux-compose return` when the compose
  nvim quits): the box becomes that text;
- `@compose-editor fullscreen` (set by the Ctrl+Shift+G binding): nvim in
  Claude's place.

Everything else that runs `$VISUAL` gets `$EDITOR`.

## Using it

- Open new shells, then start Claude in them: a Claude started before keeps its
  old `VISUAL` and gets the previous Alt+V behavior (no pull; the draft stays
  parked on quit).
- Ctrl+Shift+G needs the current `configs/wezterm.lua` (or the Windows Terminal
  keybindings), which send it as `\e[27;6;71~`.

## Open questions and checks

- **Ctrl+G while Claude is busy.** Unverified whether Claude runs its editor
  mid-turn. If not: returning the draft falls back to a paste after 3 s, and
  Alt+V opens the pane after 1.5 s without the box text. If Claude then runs
  the delayed Ctrl+G later, it pulls the box (with the pasted draft) back into
  compose.
- **A stale fullscreen request.** If Ctrl+Shift+G's Ctrl+G is never handled,
  `@compose-editor fullscreen` stays on the pane and the next Ctrl+G opens
  fullscreen instead of pulling.
- **`:q` and `:wq` are the same.** The draft autosaves, so there is no way to
  quit without returning it except `:cq`. Decide whether that is right in use.
- **Codex and OpenCode** have the same editor hook (Codex is on Ctrl+E here,
  OpenCode on Ctrl+X E) but aren't joined yet; `compose-editor` hands them to
  `$EDITOR`.
- **Ctrl+Shift+G outside Claude** reaches the program as plain Ctrl+G, because
  tmux 3.4 can't send the extended key to a pane that hasn't asked for it.

## Tests

`tests/tmux-compose-claude.sh`, with a stub that keeps a prompt box and runs
`$VISUAL` on Ctrl+G as Claude does: pull into a new and an open pane, Alt+V,
return with and without text typed meanwhile, the paste fallback, a Claude
without `compose-editor`, Ctrl+Shift+G in and outside Claude, `compose-editor`
falling back to `$EDITOR`, and with real nvim `:q`, `:cq`, and a reload after
a pull.
