# Intent keys: one key per intent, fitted to the Defy

**Status:** built (2026-10-28) on branch `keymap`, except the Defy's thumb
keys, which are set in Bazecor. The proposal page was reviewed through four
rounds; this records what was decided. Tested in private tmux servers (3.4,
3.7, 3.8) with stub agents; Shift+Tab's mode steps were also checked against
the real Claude 2.1.312. The [To check](#to-check) items need the laptop or
the real agents.

**Revised (2026-10-28), branch `mode-keys`:** Shift+Tab stepping through only
three modes felt janky, so Shift+Tab is each agent's own cycle again and three
keys on the home row jump to one mode each, a dial from most access to least:
Alt+Shift+J yolo, Alt+Shift+K auto, Alt+Shift+L edits only
([Permission modes](#permission-modes)). Checked against the
real Claude 2.1.312, Codex 0.165.0 and OpenCode 2.1.4.

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
| Alt+Shift | tmux's bigger moves | first and last window, new window, picker, full-pane compose, permission modes |
| Ctrl+Shift | WezTerm and the clipboard | tabs, copy, paste, font size, fullscreen, copy last reply |
| Shift + a non-letter | the agent's dials, and selection | Shift+Tab mode cycle, Shift+Enter new line, Shift+PgUp a few lines, Shift+arrows select |
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
| Mode cycle | Shift+Tab | native: Claude's permission modes, Codex's plan mode, OpenCode's agents |
| Yolo / auto / edits only | Alt+Shift+J / K / L | tmux, `bin/tmux-agent-mode`; see [Permission modes](#permission-modes) |
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
| tmux | Clipboard export toggle goes | done (`d29d1f0`) |
| WezTerm | Fullscreen on Ctrl+Shift+Enter; font size on Ctrl+Shift; Ctrl+Shift+G pass-through goes; ScrLk and Pause by raw code; F17/F18 rules go | done (`979d6d6`) |
| tmux | Shift+F7 review and search; Shift+F9 stop; Shift+F8 queue; Alt+Shift+V full-pane compose; Ctrl+Shift+Tab; Shift+Tab with `tmux-agent-mode`; Ctrl+Z in Claude; a click in copy-mode places the cursor | done (`979d6d6`) |
| Codex | Editor and end of line back to its defaults (Ctrl+G, Ctrl+E); `next_permission_mode` on F7; effort on Ctrl+PgUp/PgDn | done (`979d6d6`) |
| Claude | Alt+M model; Ctrl+PgUp/PgDn effort; Shift+↑↓ and Alt+P unbound | done (`9ceb032`) |
| OpenCode | Alt+M model list; Ctrl+PgUp/PgDn effort variants; TAFK delete keys; Ctrl+Z undo | done (`9ceb032`) |
| pi | New keybindings file, deployed by `bin/ai-config`: thinking level, model, TAFK delete keys, Ctrl+Z undo | done (`9ceb032`) |
| keymap | Thumb pairs rated by feel; raw keys; intents and known issues to match | done |
| Windows Terminal | The same Ctrl+Shift keys and fullscreen in `configs/windows-terminal-keybindings.jsonc`; ScrLk and Pause there need the firmware fallback. Font size keeps its defaults | done |
| tmux, Codex | Shift+Tab native again; Alt+Shift+J/K/L permission modes; Ctrl+Shift+Tab goes on to the program | branch `mode-keys` |
| tmux | Shift+PgUp in Claude adds three wheel-ups when Claude is at its bottom, which 2.1.312 holds against the first three | branch `mode-keys` |
| Defy | The four thumb keys, in Bazecor | yours to do; re-export the backup over `configs/keyboard/dygma-defy.json` |

Applying it to this machine is `bin/ai-config` (Claude, Codex, OpenCode, pi),
a tmux reload, and copying `configs/wezterm.lua` to Windows. The live
`~/.claude/keybindings.json` still has the retired Shift+Up/Down line scroll;
`bin/ai-config claude` replaces it.

## Permission modes

Three modes are in use, named the same in every agent. The keys are a dial on
the right hand's home row, access falling from J to L. Each goes straight to
its mode from wherever the agent is, and says what it did in tmux's message
line. Alt+Shift+N/M/Y were tried first; Y sat beside Alt+Shift+T (new window),
one slip from yolo, and M was one Shift from Alt+M (model picker).

| Key | Mode | Claude | Codex | OpenCode |
|---|---|---|---|---|
| Alt+Shift+J | yolo | bypass permissions | Full Access | auto accept |
| Alt+Shift+K | auto | auto mode | Approve for me | none (it has two states) |
| Alt+Shift+L | edits only | accept edits | Ask for approval | prompt |

How each agent gets there, since none has a key per mode:

- **Claude** has only its cycle, so the script presses Shift+Tab until the
  footer names the mode. Plan and ask flash by on the way. If the cycle comes
  back round, Claude wasn't started with that mode (bypass needs
  `--allow-dangerously-skip-permissions`), and the mode is left as it was.
- **Codex** picks from `/permissions` when the prompt is empty and no turn is
  running, confirming Full Access. With a draft or mid-turn it presses F7
  (`next_permission_mode`) instead, which opens the same picker on a session's
  first press and after that steps Read Only, Ask, Approve for me. Full Access
  isn't in that cycle, so Alt+Shift+J with a draft says to empty the prompt
  rather than typing over it. Each switch leaves a "Permission selection
  requested" line in Codex's transcript.
- **OpenCode** has one switch, a setting: Ctrl+P, Permissions, flip. It's
  saved to its `cli.json`, so it applies to every OpenCode session.
- **pi** never asks, so the keys only say so.

## To check

1. On the laptop: set `debug_key_events = true` in WezTerm and press ScrLk and
   Pause. A `RawKeyEvent` line with `raw_code: 145` or `19` means the raw
   bindings work; none means the firmware fallback.
2. ~~`tmux-agent-mode` against real Claude~~: done for the jump keys, with
   bypass available; without it is covered by the stub test.
3. Whether Codex, OpenCode and pi attach a pasted image path the way Claude
   does.
4. ~~OpenCode's permission dialog keys~~: the setting is reached by Ctrl+P.
