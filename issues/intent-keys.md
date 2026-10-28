# Intent keys: one key per intent, fitted to the Defy

**Status:** building (2026-10-28), on branch `keymap`. The proposal page was
reviewed through four rounds; this records what was decided. Built so far:
review's selection keys and WezTerm's search (commit `db657a1`). The rest is
listed under [Build](#build) with its state.

## Goals

From the request that started it:

- The same intent answers on the same key in every program: WezTerm, tmux,
  bash, nvim, Claude Code, Codex, OpenCode and pi.
- Left-hand-only chords only for what you do with the right hand on the mouse;
  everything else spreads across both hands.
- Mnemonics where they come cheap.
- Each modifier belongs to one layer of the stack.
- The Defy's real ergonomics, not a generic keyboard's: Ctrl, Alt and Shift all
  sit on the left hand. Ctrl+Symbols is one thumb laid across two keys, and
  easy; Ctrl+Alt is hard; Alt+Shift (thumb and pinky) is easy.
- TAFK's ESDF diamond stays.

## Who owns each modifier

| Modifier | Owner | Examples |
|---|---|---|
| Ctrl | the program in the pane | Ctrl+R history, Ctrl+PgUp/PgDn effort, Ctrl+Z undo, Ctrl+B background, Ctrl+D exit |
| Alt | tmux, and readline's line edits | Alt+E/S/D/F panes, Alt+1…0 windows, Alt+V compose, Alt+Bksp/Del |
| Alt+Shift | tmux's bigger moves | first and last window, new window, picker, full-pane compose |
| Ctrl+Shift | WezTerm and the clipboard | tabs, copy, paste, font size, fullscreen, copy last reply |
| Shift + a non-letter | the agent's dials, and selection | Shift+Tab mode, Shift+Enter new line, Shift+PgUp a few lines, Shift+arrows select |
| Symbols layer | movement | E/S/D/F arrows; with Ctrl, word jumps |
| Win | Windows | dictation, desktops |
| Thumb keys | one-tap intents | New line, Queue, Image |
| ScrLk, Break | their classic jobs | ScrLk freezes the scrollback to read it (review); Break interrupts |

One deliberate exception: Alt+M picks a model in the agents. M is the only good
letter, and Ctrl+M arrives as Enter in Codex and OpenCode.

## Decisions

### The Defy

The four empty thumb keys get one chord each, as the Copy and Paste keys
already do. Bazecor codes are for the backup file.

| Key | Sends | Code | For |
|---|---|---|---|
| Right thumb, beside Symbols (74) | Ctrl | 224 | Ctrl chords on left-hand keys turn two-handed; Ctrl+Alt becomes cross-hand |
| Right thumb, beside Enter (78) | Ctrl+J | 269 | New line: the one new-line key every agent and key mode agrees on |
| Right thumb, outermost (79) | Shift+F8 | 2113 | Queue a message for after the turn |
| Left thumb, under Copy (71) | Ctrl+Alt+V | 793 | Paste a screenshot: WezTerm uploads it to the host |

ScrLk and Pause keep their codes. WezTerm's Windows key table has no names for
them, so they never become key events, but WezTerm offers every key to its
bindings by Windows key code first: `raw:145` and `raw:19`. If a check on the
laptop shows Windows doesn't deliver them at all, the firmware sends Shift+F5
(2110) and Shift+F9 (2114) from those positions instead.

Options, not planned: Alt on the "← desk" key (73) makes Alt chords two-handed;
Shift on Caps Lock gives a right Shift, which fixes Ctrl+Shift+A (Shift and A
share the left pinky).

### By intent

| Intent | Key | How each program gets it |
|---|---|---|
| Submit | Enter | native everywhere |
| New line | New line key (Ctrl+J), or Shift+Enter | native everywhere; Ctrl+J also gets round Codex hearing Shift+Enter as Enter |
| Queue a message for after the turn | Queue key (Shift+F8) | tmux sends Claude and OpenCode Ctrl+X Enter, Codex Tab, pi Alt+Enter |
| Compose box | Alt+V | tmux (unchanged) |
| Compose, full pane | Alt+Shift+V | tmux; with no box, it presses the program's own editor key: Claude, Codex and pi Ctrl+G, OpenCode Ctrl+X E, bash Ctrl+X Ctrl+E. Replaces Ctrl+Shift+G |
| History search | Ctrl+R | native (Claude, Codex, bash) |
| Permission mode | Shift+Tab | Claude: `bin/tmux-agent-mode` taps Shift+Tab until the footer shows accept edits, bypass permissions or auto mode, skipping plan and ask. Codex: tmux sends F7, its `next_permission_mode` (Read Only, Ask, Approve for me; Full Access stays in `/permissions`). OpenCode keeps its agent cycle |
| The agent's own Shift+Tab | Ctrl+Shift+Tab | tmux sends one plain Shift+Tab to Claude, Codex or OpenCode: plan mode and ask, when wanted |
| Reasoning effort | Ctrl+PgUp / Ctrl+PgDn | agent configs; Shift+↑↓ freed, so Shift+arrows only ever select. Claude Code and pi keep the prompt cache across an effort change on current models (the effort goes in as a message at the turn where it changes); other providers may rebuild it |
| Pick a model | Alt+M | agent configs (Codex has no key; `/model`) |
| Stop | Break, or Esc in agents | tmux sends Esc to an agent and Ctrl+C to anything else. A plain Ctrl+C would exit OpenCode and clear pi's prompt |
| Undo the last turn | Esc Esc | native (OpenCode keeps Ctrl+X U) |
| Answer a permission prompt | 1 / 2 / 3 | native (Codex numbers its options too) |
| Paste a screenshot | Image key | WezTerm's upload (unchanged) |
| Copy last reply | Shift+Copy | tmux (unchanged) |
| Undo typing | Ctrl+Z | OpenCode and pi configs; tmux sends Claude Ctrl+_. Codex has no undo. bash keeps job control |
| Read the conversation | ScrLk | review, every pane. The agents' own transcript keys stay; review uses Claude's Ctrl+O |
| Review and search | Shift+ScrLk | review, every pane |
| Select text in review | hold Shift and move; `h` toggles; a click places the cursor | Shift and `h` built: see [scrollback](scrollback-copy-compose.md) §3.3 |
| Top, bottom | Ctrl+Home / Ctrl+End | native; Ctrl makes a move bigger, as on the arrows |
| Focus a pane | Alt+E/S/D/F | tmux; at the left or right edge, the next window's facing pane, wrapping around (`tests/tmux-navigation.sh`) |
| Fullscreen | Ctrl+Shift+Enter | WezTerm; Alt+Enter goes back to the programs (pi's follow-up, Codex's and OpenCode's new line) |
| Clipboard export | always on | the toggle (`C-a E`, Pause, `CLIP OFF`) goes |
| Font size | Ctrl+Shift+= / - / 0 | WezTerm; frees Ctrl+- (undo in Claude, OpenCode and pi) and Ctrl+0 (OpenCode's tab 10) |

## Build

| Layer | Change | State |
|---|---|---|
| tmux, nvim | Review: Shift selects, `h` toggles, `v` goes | done (`db657a1`) |
| WezTerm | Search goes; Ctrl+Shift+E/D/F reach tmux | done (`db657a1`) |
| tmux | Clipboard export toggle goes | |
| WezTerm | Fullscreen on Ctrl+Shift+Enter; font size on Ctrl+Shift; Ctrl+Shift+G pass-through goes; ScrLk and Pause by raw code; F17/F18 rules go | |
| tmux | Shift+F7 review and search; Shift+F9 stop; Shift+F8 queue; Alt+Shift+V full-pane compose; Ctrl+Shift+Tab; Shift+Tab with `tmux-agent-mode`; Ctrl+Z in Claude; a click in copy-mode places the cursor | |
| Claude | Alt+M model; Ctrl+PgUp/PgDn effort; Shift+↑↓ and Alt+P unbound | |
| Codex | Editor and end of line back to its defaults (Ctrl+G, Ctrl+E); `next_permission_mode` on F7; effort on Ctrl+PgUp/PgDn | |
| OpenCode | Alt+M model list; Ctrl+PgUp/PgDn effort variants; TAFK delete keys; Ctrl+Z undo | |
| pi | New keybindings file, deployed by `bin/ai-config`: thinking level, model, TAFK delete keys, Ctrl+Z undo | |
| keymap | Thumb pairs rated by feel; raw keys; intents and known issues to match | |
| Defy | The four thumb keys, in Bazecor | yours to do; re-export the backup over `configs/keyboard/dygma-defy.json` |

## To check

1. On the laptop: set `debug_key_events = true` in WezTerm and press ScrLk and
   Pause. A `RawKeyEvent` line with `raw_code: 145` or `19` means the raw
   bindings work; none means the firmware fallback.
2. `tmux-agent-mode` against real Claude: all five modes, with bypass
   available and without.
3. Whether Codex, OpenCode and pi attach a pasted image path the way Claude
   does.
4. OpenCode's permission dialog keys.
