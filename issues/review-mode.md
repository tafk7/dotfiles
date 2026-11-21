# Review mode: turned off, to re-evaluate

**Status:** off since 2026-11-20. The code and its test stay; nothing is
deleted. Re-evaluate before building on it again or removing it.

## What it was

Review ([scrollback-copy-compose.md](scrollback-copy-compose.md) §3.3,
`bin/tmux-review`) showed a pane's whole conversation, frozen and selectable:

- ScrollLock or `<prefix> f`: a shell's history in place, in copy mode, or an
  agent's conversation, as the agent exports it, in a review pane zoomed over
  the agent. Claude's came through Ctrl+O v and `bin/compose-editor`, Codex's
  from its session file (`bin/codex-transcript`), and OpenCode's from its
  export dialog.
- Shift+ScrollLock or `<prefix> /`: the same, searching upward.
- `<prefix> o`, or `o` in review: the conversation or history read-only in an
  nvim popup with the same keys (`configs/nvim/lua/dotfiles/review.lua`).

## Why it's off

In use it was laggy and did not work well enough to rely on. What was slow
was not measured before turning it off.

## What changed

- Its keys moved to `configs/tmux-review.conf`, which `configs/tmux.conf`
  does not source. `<prefix> f`, `/` and `o`, and `o` in copy mode, are tmux's
  defaults again. ScrollLock and Shift+ScrollLock only say that review is off,
  since unbound they would type Shift+F5's escape code into the pane.
- The copy-mode keys stay (E/S/D/F, Shift to select, `h`, Ctrl+E/D between
  prompts, `/` upward). `<prefix> v` enters copy mode on what the pane shows.
- Left in place and inert while review is off: `bin/tmux-review`,
  `bin/codex-transcript`, compose-editor's `@review-file` handoff,
  `review.lua` (active only under `NVIM_REVIEW=1`), and Codex's `thread-id`
  in `terminal_title`.
- `tests/tmux-review.sh` sources `configs/tmux-review.conf`, so the code stays
  tested. `tests/tmux-keys-selftest.sh` and `tests/keymap.py` check that
  ScrollLock is off.

## Turning it back on

Source the file after `configs/tmux.conf`, at the end of `~/.tmux.local.conf`
for one machine, or by hand for one server:

```
tmux source-file "$DOTFILES_DIR/configs/tmux-review.conf"
```

To make it the default again, source it from `configs/tmux.conf`. Then undo the
tests' "off" checks and restore the README and `shell/shortcuts-index.tsv`
entries (from the commit that turned it off).

## To re-evaluate

1. Measure where the time goes in an agent review. Candidates:
   - Claude's Ctrl+O v export: Claude writes the transcript as drawn, then
     waits on its editor.
   - Waiting for the text, up to `@review-timeout`, 10 s by default.
   - Loading a long conversation into a review pane's history.
   - Starting the nvim popup.
2. Consider a faster source for Claude. `bin/tmux-last-reply` already reads
   Claude's session file directly, without driving its UI.
3. Decide what is worth keeping: shell-only review is plain copy mode, which
   `<prefix> v` already gives. If an agent review doesn't become fast and
   reliable, remove it: `bin/tmux-review`, `bin/codex-transcript`,
   `review.lua`, compose-editor's handoff, and `configs/tmux-review.conf`.
