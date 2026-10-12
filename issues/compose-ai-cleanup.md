# AI cleanup for the compose pane

**Status:** parked for design. Follows [scrollback, copy, and compose](scrollback-copy-compose.md) §5.

## Problem

The compose pane's prose profile catches mistakes word by word: Vim's spell
checker and Harper's rules, applied one at a time with `Ctrl+L`. Neither
understands what the sentence means, so garbled phrasing, a wrong word that is
spelled correctly, or a half-edited sentence stays as it is.

## Idea

One key in the compose pane sends the draft, or part of it, to a fast model
with the instruction to fix spelling, grammar, and punctuation without changing
meaning, voice, or structure, and puts the result back. `u` undoes it.

## Design questions

- **Scope.** The whole draft, the current paragraph, or a visual selection.
  Paragraph by default keeps latency and the size of each change small.
- **How to call the model.** `claude -p --model haiku` needs nothing new and
  follows the user's provider configuration (API key, gateway), but starts a
  full Claude Code process (about a second, plus hooks and plugins unless
  restricted with `--setting-sources`). A direct Messages API call is faster
  but has to reproduce the provider setup (`ANTHROPIC_BASE_URL`, headers,
  model names). Either way: no tools, a short timeout, a small token limit.
- **The draft is itself a prompt.** The cleanup model may try to answer or act
  on it. The instruction has to frame the text as data (delimited, "return
  only the corrected text"), and the result needs a guard: reject a reply
  whose length or wording drifts too far from the input, and say so instead of
  applying it.
- **Not blocking the editor.** Run asynchronously (`vim.system`), show that a
  cleanup is running, and apply the result only if the text it was based on is
  unchanged; otherwise show it for a manual merge.
- **Reviewing the change.** Replace in place with undo (fast), an inline diff
  to accept or reject (safer), or replace and briefly highlight what changed.
- **Key.** Something in the compose pane's buffer-local set, usable in insert
  mode, that doesn't collide with `Ctrl+S` (send), `Ctrl+Shift+S` (stage), or
  `Ctrl+L` (fix the last mark).
- **Cost and privacy.** Every use sends the text to the provider before the
  user chooses to send it, and costs tokens. A compose prompt goes to Claude
  anyway, but the text may also be meant for somewhere else.
- **Offline and failure.** Without a network or credentials, fail quietly with
  a message; the draft is never lost.

## Alternatives

- LanguageTool through `ltex-ls-plus`: a much larger rule set than Harper,
  local, but a large Java download and a few hundred MB of memory, and still
  rule-based.
- Leave correction to the agent reading the prompt, which copes with typos;
  this matters most for text that is also meant for people.

## Tests

A stub `claude` (or API endpoint) on PATH returns fixed text: the cleanup
replaces the paragraph and is undone with one `u`; a reply that drifts too far
is rejected with a message; an edit made while the request runs keeps the
user's text; a failing call leaves the draft unchanged.
