# Key bindings across layers

A key you press passes through five layers before a program acts on it:

1. **Keyboard firmware.** The Dygma Defy's layers, from its Bazecor export in
   [configs/keyboard/dygma-defy.json](../configs/keyboard/dygma-defy.json).
2. **Windows.** It keeps Win-key chords, Alt+Tab, Alt+Esc, Alt+F4, Ctrl+Esc
   and Ctrl+Shift+Esc for itself.
3. **WezTerm.** [configs/wezterm.lua](../configs/wezterm.lua) takes a few
   chords (tabs, clipboard, font size, fullscreen) and rewrites others into
   sequences tmux and the shells understand. It has no names for ScrollLock
   and Pause, so it binds them by Windows key code (`raw:145`, `raw:19`).
4. **tmux.** [configs/tmux.conf](../configs/tmux.conf) owns Alt and the
   Ctrl+A prefix. Some root bindings test the pane first and rewrite or pass
   the key per program.
5. **The pane program.** bash, fzf, Neovim, tmux copy mode, Claude Code,
   Codex, OpenCode or pi.

Any layer can take a key, rewrite it, or let it through. The terminal's key
encoding can also merge keys on the way in: a program that asks for no
extended keys hears Ctrl+Shift+E as Ctrl+E and Shift+Enter as Enter.

## `keymap`

`bin/keymap` reads all five layers from this checkout and traces every chord
through them to each pane program.

```bash
keymap open                    # build the map page and show it through viz
keymap why shift+tab           # one chord, layer by layer, for every program
keymap why pause codex         # ... or only some
keymap free alt                # chords the keyboard sends that nothing binds
keymap check                   # fail on broken keys not already known
```

The page has four parts:

- **The keyboard.** Each key is colored by the outermost layer that acts on it.
- **The route of the chosen key.** Includes which fingers press it, rated:
  - easy: across both hands;
  - one hand;
  - tight: one thumb on two neighbouring keys;
  - stretch: one finger or thumb needed twice.

  Two thumb pairs are rated by how they feel on the Defy rather than by
  distance: Ctrl and Symbols take one thumb laid across both, Ctrl and Alt are
  a squeeze, rated a stretch (`THUMB_FEEL` in `lib/keymap/keyboard.py`).
- **An intent table.** Checks that sibling programs answer the same action
  (new line, permission mode, effort, delete a word) on the same key. The
  keys were decided in [issues/intent-keys.md](../issues/intent-keys.md).
- **The findings,** in three groups:
  - **Broken keys:** a program or layer binds a key, but pressing it does
    something else or nothing, or no key on the Defy can send it.
  - **Rewritten on purpose:** a tmux rule for one program changes the key so
    the TAFK meaning holds.
  - **Hidden by design:** stock program keys that Alt-for-tmux and the Ctrl+A
    prefix take.

## Keeping it current

`keymap check` runs in CI. It tolerates the broken keys listed in
[configs/keymap/known-issues.json](../configs/keymap/known-issues.json) and
fails when a new one appears or a listed one is fixed. After fixing keys, or
accepting new ones, run `keymap check --update`.

- **Keyboard:** after changing the Defy in Bazecor, export a backup
  (Preferences > Backup) over `configs/keyboard/dygma-defy.json`.
- **Agent defaults:** none of the agent CLIs prints its built-in keys, so
  `keymap defaults` reads them from the installed tools into
  [configs/keymap/defaults](../configs/keymap/defaults):
  - Claude Code: the binary;
  - Codex: `keymap.rs` at the installed tag;
  - OpenCode: the binary;
  - pi: its package.

  Run it after `ai-update` and commit the diff. Your own settings stay in the
  usual configs: `configs/ai/claude/keybindings.json`, the `[tui.keymap]`
  tables in `configs/codex.defaults.toml`, `keybinds` in
  `configs/opencode-cli*.json`, and `configs/ai/pi/keybindings.json`. They're
  applied on top.
- **Intents:** rows live in
  [configs/keymap/intents.json](../configs/keymap/intents.json). Each row names
  the TAFK key and, per program, the action ids that count.

## How each program hears keys

How well each program hears keys under tmux decides which chords survive:

| Program | Keys it asks for | What that means |
|---|---|---|
| Claude Code, pi, Neovim | modifyOtherKeys 2 | every chord arrives distinct |
| OpenCode | modifyOtherKeys 1 | Ctrl+Shift+letter arrives as Ctrl+letter, Ctrl+I as Tab |
| Codex | modifyOtherKeys 2 only when tmux sets `extended-keys-format csi-u`; otherwise plain keys | with plain keys, Shift+Enter is Enter and Ctrl+Shift+letter is Ctrl+letter |
| bash, fzf | plain keys | Ctrl+Backspace arrives as Ctrl+H |

These were read from live panes (`#{pane_key_mode}`) and are recorded in
`lib/keymap/route.py`.
