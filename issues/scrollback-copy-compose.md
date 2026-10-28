# Spec: scrollback, copy, and compose for agent panes

**Status:** implemented and checked by hand through phase 4. Phase 5, one
review viewer for every agent, implemented and checked against the real agents
on an isolated tmux server; it absorbs [Codex keyboard
review](codex-review-popup.md). Replaces the parked Claude fullscreen-renderer
issue and the split-pane prose-editor draft.
**Problem:** Claude Code, Codex, and OpenCode now draw their conversations on
the terminal's alternate screen, where tmux copy-mode cannot see them. Each app
scrolls, searches, selects, and copies differently; copies land in the tmux
buffer, the Windows clipboard, or both, depending on who made them; and the
only way to write a long prompt in an editor hides the conversation.
**Goal:** one gesture per intent across shells, Claude, Codex, and OpenCode;
every copy reaches the Windows clipboard; prompts are composed in Neovim with
spelling and grammar help while the conversation stays visible and live.

Verified 2026-10 against Claude Code 2.1.311, Codex 0.164.0, OpenCode 2.1.4,
tmux 3.7c, Neovim 0.12.5, and WezTerm 20240203 (on the `ssh.exe` path from
Windows); items 1–15 of §1.2 were first verified against Claude Code 2.1.287,
Codex 0.160.0–0.162.1, and OpenCode 2.0.22. "Spike" means tested on an
isolated tmux server loaded with `configs/tmux.conf` and a captured client
standing in for WezTerm; "source" means read in the tagged release (Codex
`rust-v0.164.0`, OpenCode `v2.1.4`); "docs" means
[code.claude.com/docs](https://code.claude.com/docs/llms.txt).

---

## 1. Findings

### 1.1 The three agents

| | Claude Code | Codex | OpenCode |
|---|---|---|---|
| Fullscreen | `tui: "fullscreen"`; default depends on install history while nonessential traffic is off | Default (`tui.fullscreen_transcript = true`, `tui.alternate_screen = "auto"`) | Always, for the full interface |
| Mouse capture | `CLAUDE_CODE_DISABLE_MOUSE` / `_CLICKS` | On; off only when tmux `mouse` is off | `mouse` in `cli.json` |
| Inline alternative | Classic renderer (`tui: "default"`, `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`) | `fullscreen_transcript = false` or `--no-alt-screen` (§1.2.21) | `opencode mini`, without copy or export (§1.2.25) |
| Scroll keys | PgUp/PgDn (half page), Ctrl+Home/End, wheel | PgUp/PgDn, Ctrl+Home/End, Alt+`<`/`>`, wheel | PgUp/PgDn (half page), Ctrl+Home/End (from `cli.json`) and Home/End, Ctrl+Alt+Y/E (line), wheel |
| Transcript search | `Ctrl+O`, then `/`, `n`/`N`, `{`/`}` between prompts | `F3`, then Ctrl+P/Ctrl+N | none (the timeline filters prompts only) |
| Start a selection from the keyboard | no (§1.2.18) | `Ctrl+Space`, anchored at the top-left of the view (§1.2.19) | no (§1.2.23) |
| Extend / copy a selection | Shift+arrows, Shift+Home/End; `Ctrl+Shift+C`, `Ctrl+C`; copy on mouse release | arrows; `Ctrl+C`, `Ctrl+Shift+C`, `Ctrl+Insert`, Enter; copy on mouse release in tmux | mouse only; copy on release |
| Copy the last reply | `/copy [N]` (picker when code blocks exist) | `Ctrl+O`; `/copy` steps back through older blocks and prompts | `C-x y` (`messages.copy`) |
| Transcript as text | `Ctrl+O [` into scrollback; `Ctrl+O v` to `$VISUAL` (§1.2.16); `/export [file]` | `/export [file]`: Markdown, from the prompt box | `C-x x` export dialog: Markdown to a temporary file; `session.copy` to the clipboard |
| Session of a pane | `sessions/<pid>.json` names it | `thread-id` in `tui.terminal_title` (§1.2.22) | not discoverable (§1.2.23) |
| Copy route inside tmux | `tmux load-buffer -w`, plus OSC 52 raw and passthrough-wrapped | arboard; `tmux load-buffer -w` unless `set-clipboard` is off, else passthrough OSC 52 (≤100,000 bytes) | native clipboard (not over SSH) and passthrough OSC 52 (≤8 MiB) |
| Non-interrupting submit | `Ctrl+X Enter` (`chat:queueSubmit`) | `Tab` (queue key) | `C-x Enter` (`prompt.queue`) |
| Config | `settings.json`, `keybindings.json` | `config.toml` `[tui]`, `tui.keymap.*` | `~/.config/opencode/cli.json` |

### 1.2 Verified behavior

1. **OSC 52 escapes tmux through passthrough.** With `set-clipboard off`, a
   plain OSC 52 is dropped; a passthrough-wrapped one reaches the terminal
   unbounded and skips the tmux buffer, because `allow-passthrough` is on
   (spike). Any program in a pane can therefore already set the Windows
   clipboard, so the "off is safer" claim in `bin/tmux-copy` is wrong.
2. **`after-load-buffer` fires for every external `tmux load-buffer`**; it
   does not fire for copy-mode copies (spike). In the hook, `#{buffer_name}`
   is the newest automatic buffer, not the loaded one; `#{hook_flag_b}` holds
   the `-b` name (test).
   Producers: Claude, nvim (its clipboard provider resolves to tmux), shell cut
   widgets.
3. **Fullscreen keeps the prompt live while scrolling.** In Claude, PgUp
   scrolls the conversation; typing leaves the view where it is and the
   `Jump to bottom` button stays (spike). Codex returns to the latest message
   only on Enter in an empty composer (source).
4. **Claude's transcript dump is fast.** `Ctrl+O [` on a resumed copy of the
   largest local session (34 MB of JSONL) wrote 5,710 lines into tmux history
   in about 1.2 s, and sent 5.9 KB to the terminal, because tmux redraws only
   the final screen (spike). Each dump appends a full copy: two dumps of a small
   session went from 442 to 880 lines. Claude overwrites the screen from the
   top rather than scrolling it away, so with the history cleared first a
   second review still leaves exactly one copy (spike). Claude leaves the
   alternate screen at once but writes nothing for up to about a second while
   it prepares the dump (0.5 s for 34 MB), so "history stopped changing" is
   not a completion signal until history has started to grow (spike, fixed
   after the first live test).
5. **Claude blanks its screen during `Ctrl+G`.** While the external editor runs,
   the pane stays on the alternate screen but shows nothing (spike), and Claude
   reads no input until the editor exits. An editor in a split below would sit
   under an empty, frozen pane.
6. **A bracketed paste from tmux lands intact in Claude's prompt**, and
   `Ctrl+X Enter` submits it (spike). Codex's `Tab` submits when idle and
   queues while a turn runs (source). OpenCode's `prompt.queue` submits in
   queue mode (binary).
7. **Key collisions.** tmux `M-r` swallows Codex's raw-output toggle; tmux
   `M-Up`/`M-Down` swallow OpenCode's alternate tab keys, though `Ctrl+Tab`
   reaches it (user-verified from WezTerm); WezTerm consumes `Ctrl+Shift+C`
   (Claude's selection copy); tmux's default `C-MouseDown1Pane` (swap with
   marked pane) pre-empts Ctrl+click in every app.
8. **tmux vi copy-mode `D` copies to end of line and exits.** It is live today,
   so a stray Shift+D copies and leaves copy-mode.
9. **Claude's dump marks prompts with `❯ ` at column 0** and replies with `●`.
   It emits no OSC 133 marks, so tmux's `previous-prompt` does nothing there
   (spike).
10. **Codex's live view already uses Ctrl+Home / Ctrl+End** for top and bottom;
    plain Home/End stay with the composer (spike, Codex 0.161.0).
11. **OpenCode's `C-x y` copies the last reply** without a selection, through
    OSC 52 only (spike).
12. **Claude's keybindings have no name for Insert**, so `ctrl+insert` can't
    be bound to `selection:copy`; tmux sends Claude `Ctrl+Shift+C` instead.
    Sent to an app that hasn't asked for extended keys, tmux turns that into a
    plain `Ctrl+C`; Claude asks for them (`pane_key_mode` is `Ext 2`) (spike).
13. **Fullscreen Codex has no transcript pager.** `Ctrl+T` switches the same
    view to a detailed one in place, and the `tui.keymap.pager` keys apply only
    to the overlay of the inline mode; `F3` searches the full transcript,
    paging older history in as needed (Codex 0.162.1, live test; 0.164.0,
    source: `app_backtrack.rs`, `transcript_view/search.rs`).
14. **OpenCode V2's `C-x x` opens an export dialog**, not `$EDITOR`. Tab
    cycles Markdown, JSON, thinking, tools, Copy, Export; Export writes
    `session-<id>.md` to the temporary directory and shows its path (spike).
    In 2.1.4 one Shift+Tab from the dialog's first item lands on Export, and
    the file is written by OpenCode's background service, so it lands in the
    service's temporary directory (`/tmp` here), not the pane's `$TMPDIR`
    (spike). The Markdown has `## User` and `## Assistant` headings.
15. **Alt+C is fzf's directory-jump widget** in both shells (`fzf --bash`,
    `fzf --zsh`, configured in `shell/fzf.sh`), so compose uses Alt+V, which is
    unbound in bash, zsh, tmux, WezTerm, Claude (on Linux), Codex, and
    OpenCode.
16. **Claude's `Ctrl+O v` hands its transcript to `$VISUAL`.** It writes
    `$TMPDIR/cc-transcript-<16 hex digits>.txt` (mode 600; the conversation
    as drawn, hard-wrapped at the pane's width, prompts marked `❯ ` at column
    0, tool output expanded), runs `$VISUAL` (else `$EDITOR`) on it as a direct
    child with `TMUX_PANE` set, then stays in the transcript view, and leaves
    the file behind (spike, 2.1.311).
17. **Claude stops while its editor runs.** A `sleep 6` Bash call that
    finished while a `Ctrl+O v` editor was open completed only when the editor
    exited, 28 s into the turn: the whole process waits, not just the input
    (spike). An editor that returns at once costs about 0.5 s from `Ctrl+O` to
    the hand-off, works mid-turn, and the turn goes on (spike).
18. **Claude can't start a selection from the keyboard.** The `Scroll`
    context's `selection:extend*` actions (Shift+arrows, Shift+Home/End) only
    extend a selection the mouse started; there is no action that starts one
    (docs: fullscreen, keybindings). `/copy [N]` copies the Nth-latest reply,
    with a picker when it holds code blocks; `/export [file]` writes the
    conversation as plain text; both are typed into the prompt box. A
    `command:<name>` binding runs a slash command from a key, without
    arguments (docs).
19. **Codex starts a selection with `Ctrl+Space`**, anchored at the top-left
    cell of the view; arrows move its end, `Ctrl+C`, `Ctrl+Shift+C`, or
    `Ctrl+Insert` copy, Enter copies and returns to the latest message, Esc
    clears. The keys are fixed, not in `tui.keymap` (source:
    `transcript_view/input.rs`). Through tmux, `Ctrl+Insert` copied the
    selected lines as logical text by passthrough OSC 52 (spike). Mouse
    selections copy logical source text, without display wrapping (source).
20. **Codex exports from the prompt box only.** `/export` offers "Copy to
    clipboard" or "Save to file" (Markdown); `/export FILE` writes directly;
    `/copy` copies the last reply or steps back through older code blocks,
    blockquotes, and prompts (source). Typing either into a box that holds a
    draft would append to the draft. Codex's copies go through arboard, then
    `tmux load-buffer -w` only when tmux `set-clipboard` isn't off, else a
    passthrough OSC 52 of at most 100,000 bytes (source:
    `clipboard_copy.rs`); here they reach the Windows clipboard and never the
    tmux buffer (spike).
21. **Codex's inline mode puts history in tmux's scrollback, until a
    resize.** With `fullscreen_transcript = false`, `alternate_screen =
    "never"`, or `--no-alt-screen`, finished history is written to the normal
    screen, hard-wrapped at the width (logical lines in raw mode, Alt+R). A
    width change sends `ESC[2J ESC[3J` and replays about 1,000 rows, which
    clears the pane's tmux history (source: `insert_history.rs`,
    `custom_terminal.rs`). `auto` picks inline only for Terminal.app over SSH.
22. **A Codex pane can name its thread.** The TUI holds no session file (the
    app-server daemon writes `sessions/YYYY/MM/DD/rollout-<time>-<thread>.jsonl`
    under `CODEX_HOME`), and `CODEX_THREAD_ID` is set only for the commands the
    agent runs (source). The `tui.terminal_title` item `thread-id` writes the
    thread's UUID into the pane title, cut to 29 characters and `...`; the
    prefix still names one rollout file (spike). Rollouts carry the
    app-server's thread items as `item_completed` events: `UserMessage`,
    `AgentMessage`, `CommandExecution` (command, `aggregated_output`),
    `FileChange` (unified diffs), `McpToolCall`, `Reasoning`,
    `ContextCompaction` (local rollouts). The default title is `activity`,
    `thread-name`, `project-name`.
23. **OpenCode has no keyboard selection, search, or session handle.**
    Selection is mouse-only and copies on release (`terminal.copy`); there is
    no find command. `messages.copy` (`C-x y`) copies the last reply's text,
    `session.copy` (unbound) the whole transcript as Markdown,
    `session.timeline` (`C-x g`) lists prompts with a Copy action. `opencode
    session export ID` prints JSON only, and nothing tells which session a
    running TUI shows: its title is `OC | <session title>` (source:
    `routes/session/index.tsx`, `config/keybind.ts`).
24. **OpenCode always wraps OSC 52 for tmux** and also tries the native
    clipboard, which it skips over SSH; writes are capped at 8 MiB (source:
    OpenTUI `terminal.zig`, `clipboard.ts`).
25. **`opencode mini` is inline but resets history on resize.** Output goes to
    scrollback above a redrawn footer; a resize sends `ESC[2J ESC[3J` and
    reprints the newest messages; it has no copy or export commands (source).
26. **tmux takes prompt marks and wrapping from any program.** OSC 133 `A`
    printed by a viewer, not a shell, makes `previous-prompt` and
    `next-prompt` stop at those lines, and copy-mode copies a soft-wrapped
    line as one line (tmux 3.4 and 3.7c, test). tmux 3.4's copy-mode search
    misses text on wrapped lines; 3.7c finds it (spike).

---

## 2. Model

- **The app owns its transcript; tmux owns panes, review, and the clipboard
  funnel.** Inline modes stay available but are not the design target: Claude's
  agent view and attached sessions are always fullscreen, and `opencode mini`
  is a reduced interface.
- **The modifier picks the layer.** Plain keys and clicks go to the app; Alt
  goes to tmux; Shift on the mouse goes to WezTerm; `C-a` is tmux commands.
  Copy/Paste keys: plain is the Windows clipboard, Alt is the tmux buffer.
- **Two ways to read.** *Browse* is live: the app scrolls and the prompt stays
  usable. *Review* is frozen: tmux copy-mode with one key table in every pane,
  on a shell's own history or on an agent's conversation, so search, keyboard
  selection, and copy are the same keys in Claude, Codex, and OpenCode. None of
  the three can start a selection from the keyboard in a way that lines up
  with the others (§1.1), so review is where keyboard selection lives.
- **Ask the agent, don't scrape it.** An agent's conversation comes from the
  agent's own export or session record, never from its screen; the agent keeps
  running, and nothing waits on its interface longer than the export takes.
- **Compose beside, never instead.** Prompts are written in a Neovim pane below
  the target and pasted in; the agent is never blocked.

---

## 3. Key surface

★ new, Δ changed in phases 1–4; **5** new or changed in phase 5. Unmarked
entries keep the earlier behavior.

By intent:

| Intent | Keys | Shell | Claude | Codex | OpenCode |
|---|---|---|---|---|---|
| Scroll | PgUp/PgDn, Ctrl+Home/End, wheel | copy-mode, which exits at the bottom | the agent scrolls; the prompt stays live | same | same |
| Scroll a few lines | **5** Shift+PgUp/PgDn (`@scroll-lines`, default 3) | copy-mode, which exits at the bottom | wheel events: 3 | wheel events: 3 | a wheel event: 1 (3 lines each) |
| Review | ScrollLock, `C-a f` | copy-mode on the pane | **5** its transcript, from `Ctrl+O v`, in a review pane | **5** its session file as Markdown, in a review pane | **5** its export, in a review pane |
| Search | **5** `C-a /`; `/` in review | incremental search upward in review | same | same | same |
| Start a selection | `v` in review, or Shift+arrows / E S D F | same | same | same | same |
| Extend it | Shift+arrows / E S D F, or moves after `v` | same | same | same | same |
| Copy it | `y` or Copy in review | tmux buffer and Windows clipboard | same | same | same |
| Copy the app's own selection | Copy | — | `Ctrl+Shift+C` | **5** `Ctrl+Insert` (its `Ctrl+Space` or mouse selection) | copies on mouse release |
| Copy the last reply | `C-a y`, Shift+Copy | — | from its session file: tmux buffer and clipboard | `Ctrl+O`: clipboard | `C-x y`: clipboard |
| Open in editor | **5** `C-a o`; `o` in review | history in the nvim popup | transcript | Markdown | Markdown |

### 3.1 Panes and windows

| Key | Action |
|---|---|
| Alt+E / Alt+D | Pane up / down; stops at the edge |
| Alt+S / Alt+F Δ | Pane left / right; at the outer edge, previous / next window, landing on its facing pane (`{right}` / `{left}`). Wraps around past the first and last window |
| Alt+Shift+S / Alt+Shift+F ★ | First / last window |
| Alt+arrows Δ | Same as Alt+E/S/D/F |
| Alt+1…0 | Window 1–10 |
| Alt+W / Alt+R Δ | Unbound: Alt+S/F cover them; Alt+R reaches Codex again |
| Alt+Shift+W / Alt+Shift+T | Window picker / new window after this one |
| **Alt+V** ★ | Open or focus the compose pane (§5) |

### 3.2 Browse (live)

| Key | Shell pane | Claude / Codex / OpenCode | Other fullscreen apps |
|---|---|---|---|
| PgUp / PgDn Δ | PgUp enters copy-mode a page up; it exits at the bottom | the app scrolls | the app |
| Wheel | copy-mode | the app scrolls | the app, or PgUp/PgDn if it doesn't take the mouse |
| Ctrl+Home / Ctrl+End Δ | Ctrl+Home enters copy-mode at the top | top / bottom | the app |
| Shift+PgUp / Shift+PgDn **5** | Shift+PgUp enters copy-mode a few lines up; it exits at the bottom | the app scrolls a few lines | the app |

Shift+PgUp/PgDn move `@scroll-lines` lines (default 3) wherever the pane is:
in copy-mode and review the view moves; Claude, Codex, and OpenCode get as
many mouse-wheel events as make the lines (`bin/tmux-scroll`); a compose pane
scrolls its agent; the review popup scrolls its nvim. The wheel is what the
three agents share: Codex 0.164's live view scrolls by keyboard only a page at
a time, Claude's line scroll is a keybinding (`scroll:lineUp`) and OpenCode's
is Ctrl+Alt+Y/E. Measured on Claude 2.1.311, Codex 0.164.0, and OpenCode 2.1.4,
a wheel event scrolls Claude and Codex one line and OpenCode three. Claude
speeds up wheel events that come quickly, so a held key would scroll faster
and faster there; `configs/claude-settings.defaults.json` turns that off
(`wheelScrollAccelerationEnabled`), which also keeps a quick spin of the real
wheel at one line a notch. Following the bottom, Claude's first step up moves
one line. A Claude with `CLAUDE_CODE_SCROLL_SPEED` (or `/scroll-speed`) set
scrolls that many times farther.

### 3.3 Review (frozen)

**ScrollLock** ★ toggles review (laptop: `C-a f`). **5** `C-a /` reviews and
opens the search prompt at once; **5** `C-a o` opens the conversation or history
in the nvim popup (§3.4). `C-a v` stays plain copy-mode of what the pane shows,
so a Claude pane's live prompt can be selected.

| Pane | Review shows |
|---|---|
| Shell, or any app whose output is in tmux history, including an agent off the alternate screen (Claude's classic renderer, Codex's inline mode) | the pane itself, in tmux copy-mode |
| Claude **5** | Claude's transcript as drawn, from `Ctrl+O v` (§1.2.16). Claude's `$VISUAL` is `bin/compose-editor`, which, asked through the pane option `@review-file`, moves the file there and returns at once, since Claude stops while its editor runs (§1.2.17); `Ctrl+O` then closes Claude's transcript view, unless it was open before. A Claude whose `VISUAL` is something else (not started from a dotfiles shell), or a compose-editor from before phase 5, would run that editor in its place and stop; it gets its own transcript view instead, where `/` searches |
| Codex **5** | its session file as Markdown (`bin/codex-transcript`): the thread named by the id in the pane title (§1.2.22; `terminal_title` in `configs/codex.defaults.toml`), else the newest session started in the pane's directory, which the first line says. Nothing is sent to Codex |
| OpenCode **5** | its export dialog driven to Export (`C-x x`, Shift+Tab, Enter; §1.2.14). Esc closes the "Session exported" notice 0.3 s after it shows, and again only if it is still there a second later: on its own, Esc interrupts a running turn |

An agent's text opens in a *review pane*: a split zoomed over the agent's
window, in copy-mode at the bottom. It prints the text once, with control
characters removed, and puts an OSC 133 mark before each prompt (Claude's `❯ `
lines, the Markdown's `## User`), so prompt jumps work as in a shell
(§1.2.26). The agent keeps running and stays live underneath; it receives only
the keys of its own export. Leaving copy-mode (`q`, `Esc`, `y`, ScrollLock)
removes the pane and gives focus, and the window's zoom, back to the agent.
Each review is a fresh copy, so nothing piles up in the agent pane's history.
`@review-timeout` (seconds, default 10) bounds the wait for Claude's
transcript.

Inside review, in every pane:

| | Plain | Ctrl |
|---|---|---|
| E / D (and ↑ / ↓) | line up / down | previous / next prompt |
| S / F (and ← / →) | character left / right | word left / right |
| Home / End | start / end of line | top / bottom |

Shift is the selection switch, as in a Windows text box: any of these moves
with Shift added (Shift+E, Ctrl+Shift+F, Shift+End, Ctrl+Shift+Home) starts a
selection or extends it, and a move without Shift drops it. `h` instead starts
a selection that plain moves extend, until `h` or `Esc` ends it. Paging,
scrolling and search keep a selection, so it can run past a screen.

| Key | Action |
|---|---|
| PgUp / PgDn | page up / down |
| Shift+PgUp / Shift+PgDn **5** | a few lines up / down (`@scroll-lines`) |
| `/` Δ | incremental search upward (review starts at the bottom); `?` downward |
| `n` / `N` | next / previous result in the search's direction |
| `h` | start a selection that plain moves extend, or end it |
| `y`, Alt+Copy, Copy ★ | copy the selection and exit |
| `o` ★ | open what review shows in the nvim popup, at the same line (§3.4) |
| `Esc` | clear the selection, otherwise exit |
| `q`, ScrollLock | exit |

Displaced copy-mode defaults: `e` (word end), `f`/`F`/`t`/`T` (jump to
character), `h` (left), `v` (start a selection), `o` (other end of selection),
`D` (copy to end of line),
`Ctrl+E`/`Ctrl+D`/`Ctrl+F` (scroll). `j`/`k`/`g`/`G` stay as undocumented
aliases.

Prompt jumps use tmux's `previous-prompt`/`next-prompt`, which follow OSC 133
marks: the shell prints them (`shell/init.sh`), and so does the review pane.
**5** The phase 3 search for `^❯ ` in Claude's dump is gone with the dump.

### 3.4 Open in editor

**5** `C-a o` opens the conversation (the text review would show; Markdown
with whole lines for Codex and OpenCode) or a shell pane's history read-only in
nvim, in a `display-popup` covering about 90% of the window, at the end. `o` in
review opens what review shows (`capture-pane -J -S -`, so lines wrapped only
by the screen width stay whole), at the line being viewed. `q` closes the
popup and returns to where it was opened.

**5** The popup has review's keys (`configs/nvim/lua/dotfiles/review.lua`,
loaded only with `NVIM_REVIEW`): E/S/D/F and the arrows move, Shift extends a
selection it starts, Ctrl+S/F move by word, Ctrl+E/D jump between the prompts
named by `NVIM_REVIEW_PROMPT`, `/` searches upward and `?` downward, `v`
starts or ends the selection, `y` or Copy copies it and closes the popup, and
`Esc` (with no selection) or `q` closes. Yanks go to the tmux buffer through
nvim's tmux provider, then to the Windows clipboard. nvim adds what copy-mode
lacks: line and block selection, text objects, and regular expressions.

### 3.5 Mouse

| Gesture | Shell pane | Agent pane | Fullscreen app without mouse |
|---|---|---|---|
| Click, inactive pane ★ | focus only | focus only; not passed to the app | focus only |
| Click, active pane | — | the app | — |
| Drag / double / triple-click | — | the app selects and copies on release | — |
| Wheel | copy-mode | the app scrolls | PgUp/PgDn |
| Alt+click / drag / double / triple-click | tmux selection, copies on release | same, visible screen only | same |
| Shift+drag / double / triple-click | WezTerm selection, Windows clipboard only | same | same |
| Ctrl+click Δ | unbound, so the app receives it | | |

### 3.6 Clipboard

| Key | Action |
|---|---|
| Copy (Ctrl+Insert) ★ | WezTerm already copies its own selections on mouse release. With no WezTerm selection, the key goes to tmux, which decides: in copy-mode, copy the selection; in a Claude pane, send `Ctrl+Shift+C` (`selection:copy`) while Claude reads extended keys (§1.2.12); **5** in a Codex pane, pass it on, and Codex copies its own selection (§1.2.19); anywhere else, swallow it so no stray escape sequence reaches a shell |
| Alt+Copy | Enter copy-mode, or copy the selection in it |
| Paste (Shift+Insert) | Paste the Windows clipboard (WezTerm, bracketed) |
| Alt+Paste, `C-a p` | Paste the tmux buffer, any size |
| `C-a e` | Export the newest tmux buffer now, regardless of the toggle |
| `C-a y`, Shift+Copy ★ | Copy the agent's last reply. Claude: read from its session file into the tmux buffer, without touching the draft. Codex: send `Ctrl+O`. OpenCode: send `C-x y`. Codex and OpenCode copy to the Windows clipboard only |
| Pause ★ (laptop: `C-a E`) | Toggle automatic export (`@clipboard-export`) |

---

## 4. Clipboard flow

| Source | tmux buffer | Windows clipboard |
|---|---|---|
| tmux copy-mode copies (keys and Alt+mouse) | ✓ | ★ via `tmux-copy`, ≤`@clipboard-limit` |
| nvim yanks, shell cut widgets | ✓ | ★ via `after-load-buffer` |
| Claude copies (selection, `/copy`, `/yank`) | ✓ | ✓ its own OSC 52, plus the hook |
| Codex and OpenCode copies | — | ✓ their own OSC 52 |
| WezTerm Shift+drag, Copy key with a WezTerm selection | — | ✓ |
| `C-a y` | Claude ✓ | Claude ★ via the hook; Codex and OpenCode ✓ their own OSC 52 |
| Compose sends | — (named buffer, deleted after paste) | — |

- `@clipboard-export` (default `on`) replaces the `@clipboard-osc52` test flag.
  Off stops only the ★ exports; the apps' own OSC 52 still goes through.
  Disabling `allow-passthrough` would stop those too, at the cost of every
  Codex and OpenCode copy.
- The hook skips loads with a `-b` name, so named buffers such as compose
  pastes never reach the Windows clipboard.
- Exports run in the background and skip anything over `@clipboard-limit`
  (64 KB). If WezTerm stalls on large sequences, lower the limit before turning
  the export off.

---

## 5. Compose pane

```
┌──────────────────────────────────────────────┐
│ agent pane (Claude / Codex / OpenCode)       │  stays live: PgUp/wheel scroll it,
│   conversation …                             │  the prompt floats at the bottom
│   ❯ <pasted prompt>                          │  where Send lands
├──────────────────────────────────────────────┤
│ compose pane (30%): nvim, prose profile      │  Alt+V opens or focuses
│   spell, harper-ls, Ctrl+L fixes last typo   │  Ctrl+S sends
└──────────────────────────────────────────────┘
```

### 5.1 Behavior

| Key | Where | Action |
|---|---|---|
| Alt+V | any pane | No compose pane for this pane: split below (`@compose-size`, default 30%) and open the draft. Otherwise move focus between the pane and its compose pane |
| Ctrl+S | compose, insert and normal mode | Write the draft, paste it into the target with a bracketed paste, submit with the target's non-interrupting key, clear the buffer, and append the text to the compose history |
| `,s` | compose, normal mode | Stage: paste without submitting |
| PgUp/PgDn, Ctrl+Home/End | compose | Sent to the target, so the conversation scrolls without leaving the editor |
| `:q`, `ZZ` | compose | Close the pane; the draft is kept. On a Claude, Codex, or OpenCode target, the draft goes back to the agent's prompt box instead; `:cq` keeps it |
| Ctrl+G, Ctrl+E, Ctrl+X E | Claude, Codex, OpenCode | The agent's external editor, which is `bin/compose-editor`: the prompt box moves to the end of the draft and the compose pane opens or takes focus. Alt+V in the agent does the same ([compose-agent-box.md](compose-agent-box.md)) |
| Ctrl+Shift+G | Claude, OpenCode | The prompt in nvim with the prose profile, in the agent's place |

| Target (`pane_current_command`) | Submit |
|---|---|
| `claude` | `C-x Enter` |
| `codex` | `Tab` |
| `opencode` | `C-x Enter` |
| anything else (shells) | none: Send stages, because Enter would run the command |

- The target is fixed by pane ID when the compose pane opens (`@compose_target`
  on the compose pane, `@compose_pane` on the target). If the target is gone,
  Send reports it and keeps the draft.
- Drafts live in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/compose/`, one per
  target pane (keyed by server start time and pane ID, so a restarted server
  never reopens another pane's draft), with a shared history file of sent
  prompts.
- The paste uses a named buffer (`load-buffer -b compose-<pid>`, then
  `paste-buffer -p -d`), which the export hook ignores and which is deleted
  after the paste.
- Long pastes may appear as a placeholder in the agent's prompt; the text is
  intact. OpenCode can show it in full with `prompt.paste: "full"`.
- Nothing waits on the editor, so a killed compose pane cannot hang the agent.
- Claude's box and the compose pane meet through Claude's `Ctrl+G` (plan step
  4.3): the editor it runs returns at once, so while compose is open the
  prompt lives there, otherwise in the box. Putting the draft back sets the box
  exactly, with no paste placeholder; if Claude doesn't run its editor within
  3 s, the draft is pasted instead.

### 5.2 Prose profile

`NVIM_PROSE=1` (set only by the compose pane) loads a layer after the normal
config; ordinary nvim, `git commit`, and other editors are unchanged.

- `configs/init.vim`: `if !empty($NVIM_PROSE) | lua require('dotfiles.prose') | endif`
  at the end. `configs/nvim` is already on `runtimepath`.
- `configs/nvim/lua/dotfiles/prose.lua`: `spell`, `spelllang=en_us`, soft wrap
  (`wrap`, `linebreak`, `textwidth=0`), no line numbers, `filetype=markdown`,
  ALE off for the buffer, start in insert mode, and an insert-mode `Ctrl+L`
  that fixes the latest problem before the cursor: Harper's suggested edit
  (spelling or grammar) when it has one, else Vim's first spelling
  suggestion. An AI cleanup key is parked in
  [compose-ai-cleanup](compose-ai-cleanup.md).
- Grammar: `harper-ls` through Neovim's built-in LSP client
  (`vim.lsp.config` / `vim.lsp.enable`), only when the binary is present.
  Without it the layer still provides spelling.
- Dictionaries stay untracked: Neovim's default spellfile and Harper's user
  dictionary.

---

## 6. Phases

The step-by-step execution plan, with tests and adoption checks, is in
[scrollback-copy-compose-plan.md](scrollback-copy-compose-plan.md).

| Phase | Delivers |
|---|---|
| 1 | Clipboard export: one copy path, the export hook, the Pause / `C-a E` toggle |
| 2 | Claude fullscreen with mouse capture; trimmed keybindings; focus-only clicks |
| 3 | Alt+E/S/D/F edge crossing, browse keys, review dispatch and key table, agent keymaps, prompt marks, `C-a y` |
| 4 | harper-ls; the Alt+V compose pane and prose profile |
| 5 | One review viewer: each agent's conversation in copy-mode in a review pane (Claude's `Ctrl+O v` through compose-editor, Codex's session file by the thread id in its title, OpenCode's export); `C-a /`, `C-a o`; review's keys in the nvim popup; the Copy key in Codex |

### Parked: every transcript from disk

Rendering Claude's and OpenCode's sessions from disk too would make review
independent of their interfaces and of the 50k-line history limit. Claude maps
a pane to its session through `sessions/<pid>.json`, but its JSONL is mostly
internal API records, while `Ctrl+O v` is a supported export of exactly what it
shows. OpenCode's TUI exposes no session id (§1.2.23). Revisit if a Claude
transcript outgrows the history limit or an export key changes.

---

## 7. Alternatives rejected

- **Inline modes everywhere** (Claude classic, Codex
  `fullscreen_transcript = false`, `opencode mini`): one tmux copy-mode for
  everything, but each is the secondary path in its app, Claude's agent view
  and attached sessions ignore it, and Codex's inline mode and `opencode mini`
  clear the pane's tmux history on every width change (§1.2.21, §1.2.25);
  mini has no copy or export.
- **`$EDITOR` wrapper in a split** (the original prose-editor draft): Claude
  blanks and stops reading input during the handoff (§1.2.5), so the
  conversation is neither visible nor scrollable while composing, and an
  abandoned editor pane can hang the agent.
- **Two dedicated keys for review and editor**: they overlapped in every pane
  type; the editor became `o` inside review. Phase 5 adds `C-a o` back only as
  a shortcut to the same popup, so "open in editor" is one gesture.
- **Claude's transcript dumped into its pane's history** (`Ctrl+O [`, phase 3's
  review): it needed the pane's history cleared, a settle-time heuristic to
  know the dump was done, and an Esc to bring Claude back, which interrupts a
  turn if Claude has already left the dump. `Ctrl+O v` gives the same text, and
  the editor starting is the signal that it is complete.
- **Each agent's own viewer as review** (Claude's `Ctrl+O` view, Codex's `F3`
  and `Ctrl+Space`): three sets of keys, none in OpenCode, and Codex's
  selection always starts at the top-left of the view.
- **The nvim popup as the only viewer**: one more key table to keep in step
  with copy-mode, which shells keep for their prompt marks. It stays as `o`
  and `C-a o`, for what copy-mode can't do.
- **`/export FILE` typed into Codex's or Claude's prompt box**: it would land in
  any draft there and submit it.
- **Hint copiers** (tmux-thumbs, tmux-fingers, extrakto): they read the visible
  screen, which is all tmux can capture of an alternate-screen app, and pick
  patterns such as paths, hashes, and URLs, not arbitrary text.

## 8. Open questions

1. **ScrollLock and Pause never reach WezTerm** (its key-event log shows
   nothing). The keyboard firmware sends F17/F18 from those positions instead;
   `configs/wezterm.lua` maps them to Shift+F5/F6, and tmux binds those.
   Pending: the firmware change, and whether Windows Terminal binds F17/F18.
2. **Claude's Shift+Up/Down line scroll is gone** (decided 2026-10-27):
   Shift+PgUp/PgDn scroll a few lines in every pane, so
   `configs/ai/claude/keybindings.json` keeps no overrides, and Shift+arrows
   extend a selection in Claude as they do in review.
3. **Codex panes name their thread only after a restart.** `bin/ai-config`
   adds `terminal_title` as a default; Codex sessions started before that, and
   machines that have changed their title, fall back to the newest session in
   the pane's directory, which can be another pane's.
