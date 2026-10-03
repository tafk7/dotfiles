# Claude Code fullscreen renderer, unified with tmux

**Status:** speculative — parked. Recorded 2026-10-01 against Claude Code
2.1.284 and tmux 3.7.

## User motivation and use case

Claude Code is moving toward its fullscreen renderer, which draws the session
on the terminal's alternate screen: agent view (`claude agents`) and attached
background sessions already always render this way, and new installs default
to it. The user wants to switch over fully without losing how they read and
copy conversation text today:

- Mouse: `Alt`+drag/double/triple-click into the tmux buffer, `Shift`+drag
  into the Windows clipboard via WezTerm's native selection.
- Keyboard: `C-a v` → `v` → arrows → `y` in tmux copy-mode.
- Scrolling and searching the whole session, not one screen of it.

The goal is one consistent experience across classic panes, fullscreen panes
and agent view, built from configuration plus, if it proves worth it, a Claude
Code mod.

## Current state

- `~/.claude/settings.json` sets `CLAUDE_CODE_DISABLE_MOUSE=1`, so fullscreen
  panes don't capture the mouse and the wheel falls through to tmux.
- tmux never writes alternate-screen content to pane history. In a fullscreen
  pane, copy-mode shows the visible page and then jumps to whatever the pane
  printed before it went fullscreen.
- Interim fix in `configs/tmux.conf`: on an alternate-screen pane that isn't
  capturing the mouse, the wheel sends `PgUp`/`PgDn` to the app instead of
  entering copy-mode.
- `configs/ai/claude/keybindings.json` is a full dump of an older default set,
  including actions Claude Code has since removed (`Doctor` context,
  `confirm:toggleExplanation`, `diff:viewDetails`) and `y`/`n` confirmation
  bindings that are no longer defaults.
- Path: WezTerm on Windows → `ssh.exe` (through ConPTY) → tmux on Linux.
  `config.term = 'xterm-256color'`, `bypass_mouse_reporting_modifiers =
  'SHIFT'`, tmux `set-clipboard off`, `@clipboard-osc52 off`.

## What fullscreen changes

| Workflow | Under fullscreen |
| --- | --- |
| `Shift`+drag → Windows clipboard | Still works (WezTerm bypass); visible screen only |
| `Alt`+mouse → tmux buffer | Still works (root-table bindings win); visible screen only |
| `C-a v` copy-mode | Visible screen only; tmux `/` can't search the session |
| Wheel | With mouse capture: scrolls inside Claude. Without: needs the interim binding |

Claude's own escape hatches: `Ctrl+o` opens transcript mode with `/` search;
`[` writes the whole conversation into native scrollback (all tmux tools work
until `Esc`); `v` opens it in `$EDITOR`. With mouse capture on, in-app
drag-selection copies on release to the tmux buffer, and over SSH via OSC 52.

## Levers

**Claude settings and env** (`configs/claude-settings.json`)
- `tui: "fullscreen"` explicitly; `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`
  makes the default depend on local history otherwise.
- Mouse: full capture, `CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` (wheel only), or
  `CLAUDE_CODE_DISABLE_MOUSE=1` (today).
- `CLAUDE_CODE_SCROLL_SPEED`, `wheelScrollAccelerationEnabled`.
- `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT=1` if ConPTY leaves stale fragments.

**Keybindings** (`configs/ai/claude/keybindings.json`)
- Rebindable: `app:toggleTranscript`, `transcript:exit`, every `scroll:*` in
  `Scroll` and `Transcript`, every `selection:*` in `Scroll`.
- Fixed: transcript `/`, `n`/`N`, `{`/`}`, `[`, `v`. No action starts a
  selection from the keyboard; selections begin with a mouse drag.
- `selection:copy` defaults to `Ctrl+Shift+C`, which WezTerm consumes.
- Bare letters in `Scroll` would swallow typing at the prompt.

**tmux** (`configs/tmux.conf`)
- `set-clipboard on` or `@clipboard-osc52 on` so Claude's OSC 52 copies reach
  WezTerm.
- A `C-a v` variant for fullscreen Claude panes: send `C-o [`, wait for the
  dump, enter copy-mode. Elsewhere unchanged.
- A popup transcript viewer: map the pane's Claude PID to its session through
  `claude agents --json`, render the session JSONL under
  `~/.claude/projects/` as text, open it in `less`/`nvim`. Independent of the
  renderer.

**Mods** (`github.com/anthropics/claude-code/tree/main/mods`; verified on
Claude Code 2.1.287, 2026-10-01)
- Mods are on by default from 2.1.287; `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is
  ignored. A plugin's `hooks/hooks.json` names a TypeScript module
  (`register(on, options)`).
- Relevant surface: `$.session.messages()` (newest 4096 messages as plain
  data), panes docked beside the fullscreen transcript (as `/diff` does),
  `Client` components with raw key and pointer events, `$.command.register`,
  `$.process.run`, and `$.ui.copy`, which lands in the tmux buffer even with
  `set-clipboard off`. `Button({ action })` binds to existing keybinding
  actions; there are still no custom actions and no hook into the main
  transcript's selection.
- `Image` does not render inside tmux (alt text only), so graphics in a pane
  are not an option.
- A built-in `/copy` exists and cannot be overridden. It supports the latest
  reply, `/copy N`, and individual code blocks through the terminal clipboard.
  A `/yank` pane (`plugins/yank-claude/`) adds older messages of any role and
  copies whole messages into the tmux buffer.

## Sketch if we do it

1. Trial `/tui fullscreen` in one pane with each mouse mode; confirm
   in-app copy reaches the Windows clipboard once tmux forwards OSC 52.
2. Trim `keybindings.json` to real overrides; bind `selection:copy` to a chord
   WezTerm passes through.
3. Add the tmux `C-a v` dump binding (cheap, renderer-dependent) or the popup
   viewer (more work, renderer-independent).
4. Use the `/yank` plugin for older messages and copying into the tmux buffer
   if steps 1–3 leave a gap worth an unstable API.
5. Set `tui`, mouse mode and any mod env in `configs/claude-settings.json` so
   agent view sessions match.

## Open questions

- Do installed mods load in agent view background sessions, and does the
  `settings.json` `env` reach them?
- Does Claude's OSC 52 copy travel through tmux passthrough or need
  `set-clipboard on`?
- Does ConPTY on the `ssh.exe` path leave stale fragments, or would a WezTerm
  SSH domain be needed?
- How long does `[` take on a long session, and does a tmux binding need to
  wait for it?

## When to actually pick this up

- When the classic renderer is deprecated or degrades, or agent view becomes
  the main way of working.
- When mods gain custom keybinding actions or a hook into the transcript
  selection.

## References

- https://code.claude.com/docs/en/fullscreen
- https://code.claude.com/docs/en/keybindings
- https://code.claude.com/docs/en/agent-view
- https://github.com/anthropics/claude-code/tree/main/mods (API:
  `mods/types/claude-code.d.ts`)
