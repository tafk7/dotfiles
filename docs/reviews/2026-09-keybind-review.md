# TAFK keybind review (2026-09-16)

Scope: `configs/tmux.conf`, `configs/wezterm.lua`,
`configs/windows-terminal-keybindings.jsonc`, the shell cut widgets in
`entry/bash.sh` and `entry/zsh.sh`, the vim split mappings in
`configs/init.vim`, and `docs/keyboard-layout.txt`.

Two parts: a diagnosis of the Claude Code scrollback problem first, since it
is actionable today, then the opinionated review of the key surface.

---

## Part 1: Claude Code scrollback inside tmux

### What is happening

The pane running Claude Code has the **alternate screen active**
(`#{alternate_on}` = 1). Claude Code 2.1.x ships a new "fullscreen" renderer
that switches the terminal into the alternate screen buffer (`ESC[?1049h`),
the same thing vim and less do. Once an application is on the alternate
screen, tmux has no scrollback for it: there is nothing to scroll because the
transcript never entered tmux's history. In that mode Claude Code does its own
scrolling ("virtual scroll") and expects to receive either mouse wheel events
or PgUp/PgDn.

Two settings in this dotfiles setup then collide with that design:

1. `~/.claude/settings.json` sets `CLAUDE_CODE_DISABLE_MOUSE=1`. Claude Code
   therefore never turns on mouse reporting, so the pane's
   `#{mouse_any_flag}` stays 0.
2. `configs/tmux.conf` binds `WheelUpPane` to "forward to the app if it
   reports mouse, otherwise enter copy mode." With the flag at 0, the wheel
   enters tmux copy mode over an alternate screen that has no history, so
   you see either nothing or stale pre-launch lines.

Claude Code even has a tmux-specific hint for this state, found in the
binary:

> tmux detected · scroll with PgUp/PgDn · or add 'set -g mouse on' to
> ~/.tmux.conf for wheel scroll

Your tmux already has `mouse on`, so the hint is misleading here. The real
blocker is the disabled mouse reporting.

So this is **not a tmux config bug**. It is a Claude Code renderer change
interacting with a deliberate choice (mouse off) that predates the change.

### Fixes, pick one

| Option | How | Trade-off |
|---|---|---|
| A. Go back to the classic inline renderer | Run `/tui default` inside Claude Code (preference is saved), or set `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` in `settings.json` `env` | Transcript flows into tmux history again. Alt+drag, Alt+click copy, `prefix v`, and the 50k-line history all work as before. This is the option that matches the TAFK model where tmux owns scrollback. |
| B. Keep fullscreen, use keyboard scroll | PgUp/PgDn scroll the Claude transcript. On the split board these are right-half layer 0 keys. | Wheel does nothing useful. Tmux copy mode over the transcript is unavailable, so Alt+Copy cannot grab agent output. |
| C. Keep fullscreen, re-enable mouse | Remove `CLAUDE_CODE_DISABLE_MOUSE` from settings | Wheel scroll works via Claude Code. But Claude Code now owns mouse events, so tmux's Alt+drag selection needs the app to release the mouse, and the original reason for disabling mouse (likely clicks stealing focus or selection) returns. |

Recommendation: **A**. The whole clipboard and copy-mode design in this repo
assumes tmux holds the transcript. Fullscreen mode moves that ownership into
Claude Code and quietly breaks Alt+Copy, `prefix v`, Alt+triple-click, and
the size-gated export path. If you later want fullscreen, `/tui fullscreen`
turns it back on.

Concretely, in `configs/claude-settings.json`:

```json
"env": {
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "CLAUDE_CODE_DISABLE_MOUSE": "1",
    "CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN": "1"
}
```

### Two side findings from the live server

- **`terminal-overrides` and `terminal-features` are appended three times.**
  Every `prefix r` reload runs `set -ga`, which appends rather than replaces,
  so the lists grow on each reload. Harmless for correctness, but it means
  the running server does not match a fresh load. Fix: `set -g` the first
  entry (replacing the list) and `-ga` only the rest, or guard the block.
- **Two clients are attached with different sizes.** A WezTerm client at
  162x42 and a second client whose terminal is itself tmux at 158x52. With
  `window-size latest`, whichever client last sent input dictates geometry,
  and a nested tmux client can cause the pane to resize under Claude Code,
  which triggers full repaints. If the nested client is accidental, detach
  it with `tmux detach-client -t /dev/pts/0`.

---

## Part 2: The key surface

### The philosophy as I read it

TAFK is a layered ownership model:

- **Client** (WezTerm or Windows Terminal) owns top-level tabs, one per
  machine, and the native Windows clipboard.
- **tmux** owns everything inside a machine: sessions, windows, panes,
  scrollback, and a shared buffer.
- **Shell and TUIs** own Ctrl. **Alt is reserved for tmux**, so no-prefix
  navigation is instant and identical on every host.
- **The left hand does spatial work.** ESDF is the pane diamond, the number
  row jumps windows, W and R are "shoulders" around E for stepping windows,
  and Alt+Shift holds the rarer window operations.
- **Physical Copy/Paste keys** (Ctrl+Insert, Shift+Insert on the left half)
  get an Alt-modified twin that routes to tmux's buffer instead of the
  Windows clipboard.
- **Shift on a deletion chord** means "also publish what I removed to the
  tmux buffer."

### What works well

- **Ctrl+a as prefix costs nothing on this board.** Home is a dedicated key
  on the left half, so losing readline's beginning-of-line does not hurt.
- **Alt+ESDF matches layer 1.** Arrows live on E/S/D/F in layer 1, so
  Alt+ESDF and Alt+Arrow are the same fingers with or without the layer
  thumb. That is an ergonomic fact, not just a mnemonic.
- **Cross-hand chords.** Right Alt under the right thumb plus left-hand ESDF
  is an ideal chord shape. Number row 1 to 5 and W/R stepping are cross-hand
  too.
- **Clipboard safety.** Turning off tmux's own OSC 52 while agents run in
  every pane, with a size-gated helper instead, is correct and unusual. The
  comments explaining it are excellent.
- **Destructive actions always confirm and always sit behind the prefix.**
- **Directory-based automatic window names** solve the "every window is
  called claude" problem cleanly.

### Improvements, ranked

1. **Resize is the worst chord in the system.** Prefix then Shift+Arrow
   means Ctrl+a, then left pinky on Shift, left thumb on Layer, and a left
   finger on ESDF. Three left-hand holds plus a prior chord for the most
   repeated pane operation after navigation. Alt+Shift+E/S/D/F is free (the
   config unbinds M-E/S/D/F explicitly) and is the direction-aligned answer.
   No-prefix keys repeat naturally, so `-r` and `repeat-time` stop
   mattering.

   ```tmux
   bind -n M-E resize-pane -U 5
   bind -n M-S resize-pane -L 5
   bind -n M-D resize-pane -D 5
   bind -n M-F resize-pane -R 5
   ```

2. **Alt+ESDF and Alt+Arrows disagree at the edge.** Alt+Left/Right cross
   into the neighboring window at the layout edge; Alt+s/f do not. On this
   board they are the same physical keys, so one of them will surprise you.
   Make both cross, or neither. I lean toward both crossing.

3. **Vim splits should be Alt+ESDF, not Ctrl+ESDF.** Today the same spatial
   gesture has a different modifier inside neovim, and Ctrl+E, Ctrl+D,
   Ctrl+F lose their native scroll meanings there. The vim-tmux-navigator
   pattern fixes this: tmux checks whether the pane's foreground process is
   nvim and forwards Alt+ESDF; nvim moves splits internally and hands off to
   tmux at its own edge. One gesture, one modifier, native Ctrl restored.

   ```tmux
   is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?n?vim$'"
   bind -n M-e if-shell "$is_vim" 'send-keys M-e' 'select-pane -U'
   # ... same for s, d, f
   ```

4. **Splits require the layer.** Neither `-` nor `=` exists on layer 0 of
   either half, so `prefix -` is really Ctrl+a, Layer, W. The `=` for
   side-by-side is also a weak mnemonic. `prefix D` (split below) and
   `prefix F` (split right) match the diamond and need no layer. Lowercase
   `d` stays detach. Keep `-` and `=` as aliases if muscle memory wants
   them.

5. **Alt+Copy does not copy to the clipboard by default.** With
   `@clipboard-osc52 off`, Alt+Copy in copy mode only fills the tmux buffer
   and you need `prefix e` afterwards. The key is labeled Copy, so the
   gesture promises more than it delivers. The size gate in `bin/tmux-copy`
   already solves the stall that motivated the off default. Give the two
   keys distinct meanings: `y` stays buffer-only, Alt+Copy always exports
   through the gated helper.

6. **Alt+Enter is claimed by both clients.** WezTerm binds it to fullscreen,
   and the Windows Terminal fragment leaves the default fullscreen binding
   in place. Claude Code and Codex both use Alt+Enter or Shift+Enter for a
   newline in the composer. With an agent in every window this is a daily
   annoyance. Unbind it in both fragments; F11 already covers fullscreen.

7. **Alt+f and Alt+d are stolen from readline and TUIs.** These are the two
   most-used emacs-style Alt keys, forward-word and kill-word. Prefix
   passthrough exists, but a two-step for word motion defeats the point.
   This is an inherent cost of the diamond and worth accepting. Mitigation:
   pin Ctrl+Left/Right word motion explicitly in the bash section too. zsh
   and fzf have it; bash currently relies on readline defaults.

8. **No instant zoom.** Alt+Shift+A was removed deliberately, but with agents
   in split panes zoom is one of the most frequent actions. Alt+z is unused
   by readline and by both clients. If the removal was about accidental
   triggers, lowercase Alt+z is far less prone to that than the shifted
   variant was.

9. **Window jump 6 to 0 is same-hand.** Right Alt plus a right-hand digit
   forces left Alt instead, which sits under the C column and is a cramped
   same-hand chord. Low impact if sessions stay under six windows.

10. **Cleanup residue.** The explicit `unbind -n M-E/S/D/F`, `M-G`, `M-Q`,
    `M-A`, `M-X`, and the status-drag unbinds exist only so a live reload
    clears old bindings. Once every server has been restarted they can go,
    along with the prefix arrow mirror if it is never used on a laptop.

### Smaller notes

- Ctrl+S in the vim mapping is safe only because neovim disables tty flow
  control. Plain vim would freeze the pane until Ctrl+Q.
- The uncommitted change in `entry/bash.sh` hardcodes the home directory in
  a PATH export for opencode. It should use `$HOME` and probably belongs in
  `shell/env.sh` with the other PATH composition.
- `set -s extended-keys on` plus `xterm*:extkeys` is correct for WezTerm.
  Windows Terminal's extended-key support is weaker, so if Alt+Shift chords
  ever misfire there, this is the first thing to test with `off`.

### Suggested order of work

1. Part 1 fix (one line in `configs/claude-settings.json`). Immediate relief.
2. Items 1, 2, 4, 6: tmux and client fragments only, low risk.
3. Item 5: clipboard semantics, small change to two bindings.
4. Item 3: vim integration, touches `init.vim` and tmux, needs a quick test
   with nvim in a split.
5. Items 7 to 10 as taste dictates.

Update `shell/shortcuts-index.tsv` and `tests/tmux-config.sh` alongside any
binding change so `cheat` and CI stay truthful.
