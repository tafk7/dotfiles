# Agent parity: how far pi and OpenCode should follow Claude and Codex

**Status:** open (2026-10-29). The owner's vote so far: pi stays "keys only",
not a first-class agent; record that in the docs rather than build the tools
below for it. OpenCode is undecided.

**Problem:** four agents run in tmux panes, but the tooling around them grew up
around Claude and Codex. pi and OpenCode get the intent keys
([intent keys](intent-keys.md)) and their configs, and little else. Nothing
says whether that is a decision or a backlog, so each new tool picks its own
set of agents.

## Where they stand (2026-10-29)

| Tool | Claude | Codex | OpenCode | pi |
|---|---|---|---|---|
| Intent keys (tmux routing, configs) | yes | yes | yes | yes |
| Install and config (`installers/`, `bin/ai-config`) | yes | yes | yes | yes |
| Review: the conversation in copy-mode (`bin/tmux-review`) | yes | yes | yes | no: falls back to the visible screen (`agent_transcript`, `bin/tmux-review` ~158) |
| Copy last reply (`bin/tmux-last-reply`) | yes | yes | yes | no |
| Compose box as the agent's editor (`bin/compose-editor`) | yes | yes | yes | no: Alt+Shift+V presses its Ctrl+G instead |
| Agent badge (`plugins/agent-badge`) | yes | yes | no | no |
| Explicit update (`bin/ai-update`) | yes | yes | yes | no; being folded into `dotfiles` on the `verify-unify` branch, with pi |
| viz skill (`plugins/viz-claude`) | yes | no | no | no |

## Options

1. **Keys only, documented.** pi (and OpenCode, if chosen) get the intent keys,
   install and config, and nothing else; README and `docs/` say so, and new
   tools may skip them without asking. Cheapest; it is today's state, written
   down.
2. **Read-back parity.** Review and copy-last-reply for every agent: the two
   tools for reading a conversation, which matter most when an agent draws on
   the alternate screen. pi keeps its session as JSONL, which `tmux-review`
   could render as it does Codex's.
3. **Full parity.** Option 2 plus the badge and the compose editor.

## Decision

Not yet made. Leaning: option 1 for pi. If OpenCode stays in daily use, option 2
for it, since review and last-reply already cover it and only the badge is
missing.
