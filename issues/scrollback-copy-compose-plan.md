# Execution plan: scrollback, copy, and compose

Implements [the spec](scrollback-copy-compose.md). The spec says *what*; this
says *how*, in order. Section references (§) point into the spec.

## Ground rules

- **Worktree.** All work happens on branch `scrollback-copy-compose` in a
  separate worktree (`git worktree add ~/dev/dotfiles-scc -b scrollback-copy-compose`).
  Never run `setup.sh` against the live HOME from it
  ([maintenance](../docs/maintenance.md)).
- **One step, one commit.** Each numbered step below is one commit, lands with
  the full suite green ([testing](../docs/testing.md)), shellcheck clean, and
  `git diff --check` clean. Docs, `shell/shortcuts-index.tsv`, and comments
  change in the same commit as the code they describe.
- **Phase gates.** At the end of each phase: fast-forward `main`, adopt it on
  the live machine (see "Adoption and manual checks"), run that phase's manual checks, and only
  then start the next phase.
- **Test-first where tmux semantics are assumed.** Several steps rely on tmux
  behavior inferred rather than proven (key-table precedence in copy-mode, hook
  format context, `copy-command` environment). Each such step starts with a
  failing test that pins the behavior.
- **Shared raw-key harness** (built in step 1.1) drives every tmux test the way
  WezTerm does: an inner tmux server loaded with `configs/tmux.conf`, attached
  from a pane of an outer `-f /dev/null` server through `script`, so tests can
  type raw escape sequences (`tmux -L outer send-keys -l`) and read what the
  terminal receives (the `script` log, for OSC 52).

## Phase 1 — Clipboard export

### 1.1 Raw-key test harness

- `tests/lib/tmux-keys.sh` ★:
  - `tk_start CONFIG`: inner server (isolated `TMUX_TMPDIR`, spaced checkout as
    in `tests/tmux-config.sh`), outer server running
    `script -qfc "tmux -L inner attach" LOG`.
  - `tk_raw BYTES`: type into the inner client.
  - `tk_osc52`: decode every OSC 52 payload written to the client since a mark.
  - `tk_stub NAME [PROGRAM]`: copy a binary to `$TEST_ROOT/bin/NAME` so
    `pane_current_command` reports NAME (`cat -v` by default; a Python stub for
    Claude in step 3.2).
  - `tk_wait FORMAT VALUE`: poll a pane format with a timeout.
- `tests/tmux-keys-selftest.sh`: the five Copy-key / Shift+F5 / Shift+F6 cases
  already verified by hand when `9e64fd6` landed, so the existing bindings get
  regression coverage before anything changes.

### 1.2 One copy path, one toggle

- `configs/tmux.conf`:
  - Replace `@clipboard-osc52 off` with `@clipboard-export on`.
  - `set -g copy-command '"$DOTFILES_DIR/bin/tmux-copy"'`. Test first that the
    command sees `DOTFILES_DIR` from the global environment under a checkout
    path with spaces.
  - Every copy binding uses `copy-pipe-and-cancel` with no argument, removing
    the `if-shell @clipboard-osc52` wrappers: `y`, `C-IC`, `C-M-IC`,
    `M-MouseDragEnd1Pane`, and the root and copy-mode `M-DoubleClick1Pane` /
    `M-TripleClick1Pane`.
  - `set-hook -g after-load-buffer` runs
    `"$DOTFILES_DIR/bin/tmux-copy" --hook "#{hook_flag_b}"` in the background
    (`#{buffer_name}` turned out to be the newest automatic buffer).
  - `bind E` and `bind -n S-F6` toggle `@clipboard-export` with a message,
    replacing the reserved Shift+F6 placeholder.
  - `status-right` gains a reverse-video `CLIP OFF` marker while off. Check
    that the agent-badge plugin's format injection still applies
    (`plugins/shared/README.md`).
- `bin/tmux-copy`:
  - **stdin mode** (copy-pipe): drains stdin, exports only while
    `@clipboard-export` is on; `--always` overrides.
  - **`--hook NAME`**: NAME is the load's `-b` name; exports only unnamed
    loads while on, reading `show-buffer`.
  - **`--buffer [--notify]`**: explicit export, ignores the toggle (`C-a e`).
  - Header rewritten: the size gate, the toggle, and that `allow-passthrough`
    already lets any pane set the clipboard (§1.2.1), replacing the "off is
    safer" claim.
- `shell/tools/general.sh`: `yo` calls `tmux-copy --always`.
- `README.md` (tmux clipboard paragraph), `shell/shortcuts-index.tsv` (copy
  rows, Pause / `C-a E`).
- `tests/tmux-clipboard.sh` ★:
  - copy-mode `y` and the Copy key: tmux buffer set, OSC 52 payload matches;
  - external `load-buffer`: exported; `load-buffer -b named`: not exported;
  - toggle off: no OSC 52 from copy-mode or the hook, buffer still set;
    `C-a e` still exports;
  - payload over `@clipboard-limit`: no OSC 52, message shown;
  - toggle survives `source-file` (reload keeps the current value).
- Update any test that sets `@clipboard-osc52`.

**Done when** every source in §4 reaches the expected destinations in
`tests/tmux-clipboard.sh`.

## Phase 2 — Fullscreen and mouse

### 2.1 Claude settings and keybindings

- `configs/claude-settings.json`: `"tui": "fullscreen"`; env
  `CLAUDE_CODE_DISABLE_MOUSE` becomes `"0"`, not removed, because
  `bin/ai-config` merges and would keep the live `"1"`. `"0"` enables capture
  (spike).
- `configs/ai/claude/keybindings.json`: rewrite to real overrides. Diff the
  current dump against the defaults in the binary. Anything that differs is
  listed for your confirmation before it's dropped. The asset is written
  wholesale, and `bin/ai-config` backs up the live file first.
  `ctrl+insert` turned out not to be bindable (§1.2.12): tmux sends Claude
  `Ctrl+Shift+C` for the Copy key instead, only while `pane_key_mode` is
  `Ext 2`.
- `tests/ai-config.py`: `tui` and the env value merge without disturbing local
  keys; the keybindings asset matches.

### 2.2 Click focus

- `configs/tmux.conf`: `MouseDown1Pane` on an inactive pane only selects it; on
  the active pane it selects and forwards (`send-keys -M`) as today. Unbind
  `C-MouseDown1Pane`.
- `tests/tmux-mouse.sh` ★: two panes, the right one a stub that enables SGR
  mouse reporting and logs input. A raw click on it while inactive: it becomes
  active and logs nothing. A second click: it logs the mouse sequence.

**Done when** both tests pass and the manual Phase 2 checks pass.

## Phase 3 — Navigation, browse, and review

### 3.1 Pane and window navigation, browse keys

- `configs/tmux.conf`:
  - `M-s`/`M-Left`: at `pane_at_left`, if not `window_start_flag`, run
    `previous-window` then `select-pane -t '{right}'`; at the first window,
    show a message. Otherwise `select-pane -L`. `M-f`/`M-Right` mirror it with
    `window_end_flag` and `{left}`.
  - `M-e`/`M-d`/`M-Up`/`M-Down`: move only when not at the edge. Today they
    wrap; this is a deliberate change.
  - `PPage` (root): `alternate_on` → forward; otherwise `copy-mode -eu`. Test
    first that copy-mode's own `PPage` still wins inside copy-mode.
  - `C-Home` (root): `alternate_on` → forward; otherwise `copy-mode -e` and
    `history-top`.
  - Alt+W/R unchanged; their removal is a separate later commit when you ask.
- `tests/tmux-navigation.sh` ★: two windows × two panes; edge crossing lands
  on the facing pane; stops at the first and last window; vertical moves stop
  at the edge; PgUp in a shell enters copy-mode scrolled up; PgUp and
  Ctrl+Home in an alternate-screen stub reach the stub.
- `shell/shortcuts-index.tsv`: navigation and browse rows.

### 3.2 Review

- `bin/tmux-review` ★ (`toggle PANE`, `open PANE`):
  - **toggle:** if the pane is in a mode, cancel it. Otherwise dispatch on
    `pane_current_command` and `alternate_on`:
    - `claude`: set `@review claude`, `clear-history`, send `C-o` then `[`,
      show "loading transcript…", poll until `alternate_on` is 0 and
      `history_size` has stopped changing (10 s cap), then `copy-mode` at the
      bottom. On timeout: message, send `Escape`, unset `@review`.
    - `codex`: send `F3` (changed after the live test; §1.2.13).
    - `opencode`: drive the export dialog (`C-x x`, five Tabs, Enter), take
      the exported file, close the dialog, open the popup (§1.2.14).
    - otherwise: `copy-mode`.
  - **open:** capture the pane's history with `-J` into a mode-600 temporary
    file, open `display-popup -E -w 90% -h 90%` running
    `NVIM_REVIEW=1 nvim -R` at the line being viewed, and delete the file when
    nvim exits. Position: the approximate line from `history_size`,
    `scroll_position` and `copy_cursor_y`, refined to the nearest line matching
    `copy_cursor_line`, since joined lines shift numbering.
- `configs/tmux.conf`:
  - `S-F5` (root and copy-mode) and `bind v` run `tmux-review toggle`.
  - `pane-mode-changed` hook: when `@review` is `claude` and the pane has left
    copy-mode, unset it and send `Escape`. Test first that the hook's formats
    refer to the pane that changed.
  - copy-mode-vi table (§3.3): `e/s/d/f` move; `E/S/D/F` and Shift+arrows
    begin a selection if none and extend it; `C-s/C-f` and Ctrl+Left/Right
    move by word; `C-e/C-d` and Ctrl+Up/Down jump to the previous/next prompt
    (`search-backward '^❯ '` while `@review` is `claude`, otherwise
    `previous-prompt`/`next-prompt`); `Home/End` page; `C-Home/C-End` top and
    bottom; `/` incremental search upward, `?` downward; `o` runs
    `tmux-review open`. Displaced defaults per §3.3; `t`/`T` unbound.
- `configs/init.vim` + `configs/nvim/lua/dotfiles/review.lua` ★: with
  `NVIM_REVIEW=1`, buffer-local `e/s/d/f` motions and `q` to quit.
- `tests/tmux-review.sh` ★:
  - dispatch per command with stubs: `codex` receives `^T`, `opencode`
    receives `^X x`, a shell gets copy-mode;
  - a Python stub run as `claude` that enters the alternate screen, prints a
    transcript with `❯` prompts on `C-o [`, and logs `Esc`: two reviews leave
    exactly one dump in history; leaving copy-mode sends `Esc` and clears
    `@review`; a stub that never dumps hits the timeout path;
  - key table: `E` starts a selection, `D` no longer copies, `C-e` lands on
    the previous `❯` line;
  - `o`: a stub `nvim` on PATH records its arguments and the temp file's mode
    and contents; the file is gone afterwards.
- `shell/shortcuts-index.tsv`: review rows. `tests/neovim.sh`: the review layer
  loads only with `NVIM_REVIEW`.

### 3.3 Agent keymaps, prompt marks, Windows Terminal

- `configs/codex.toml` and the reference `configs/codex-keybindings.toml`:
  `[tui.keymap.pager]` `scroll_up = ["up", "k", "e"]`,
  `scroll_down = ["down", "j", "d"]`, `jump_top = ["home", "ctrl-home"]`,
  `jump_bottom = ["end", "ctrl-end"]`. Verify Codex starts with it (it rejects
  conflicting keymaps) in an isolated `CODEX_HOME` before committing.
- OpenCode `cli.json`: overlay `configs/opencode-cli.json` ★ merged by
  `lib/ai_preferences.py` into `~/.config/opencode/cli.json`, only when the V2
  CLI is detected, preserving everything else OpenCode writes there.
  Keybinds: `session.first` `ctrl+home,ctrl+g,home,alt+home`, `session.last`
  `ctrl+end,ctrl+alt+g,end`. Ctrl+Tab is already the default for
  `session.tab.next`, so the tab keys aren't overridden. `tests/ai-config.py`
  covers the merge, preservation, and skipping on V1.
- `shell/init.sh`: in interactive shells only, mark each prompt with OSC 133
  (`\e]133;A\e\\`): bash appends a `PROMPT_COMMAND` step after Starship's that
  prefixes `PS1`; zsh adds a `precmd` function after Starship's. Fork-free.
  `tests/shell-behavior.sh`: the mark is present interactively and absent in
  agent and non-interactive shells. `tests/tmux-review.sh`: `C-e` moves
  between two commands' prompts. Run `tests/startup-benchmark.py` against the
  pre-step revision.
- `configs/windows-terminal-keybindings.jsonc`: `sendInput` actions on `f17` and
  `f18`, matching `wezterm.lua`.

**Done when** all Phase 3 tests pass, startup doesn't regress, and the manual
Phase 3 checks pass.

## Phase 4 — Compose pane

### 4.1 harper-ls

- `eget.toml`: `["Automattic/harper"]`, tag `v2.12.0`, filters
  `["harper-ls", "musl"]`. Both architectures ship a musl build, so one asset
  remains per arch.
- `lib/registry.sh`: core row `harper-ls`, method `eget`, capability `ai`;
  override `eget-repo Automattic/harper`.
- `python3 tests/eget-selection.py --refresh` to record the asset lists and
  regenerate `eget.lock`; confirm the locked extract path is the `harper-ls`
  binary.
- Docs that list `--ai` contents.

### 4.2 Compose pane and prose profile

- `bin/tmux-compose` ★:
  - **toggle PANE:** from a compose pane, focus its target; from a pane whose
    compose pane is alive, focus that; otherwise split below
    (`@compose-size`, default 30%) running nvim on the draft with
    `NVIM_PROSE=1`, `DOTFILES_COMPOSE_TARGET` and `DOTFILES_COMPOSE_DRAFT`, and
    record `@compose_target` / `@compose_pane`.
  - **send FILE** / **stage FILE:** refuse an empty draft or a dead target
    (draft kept); cancel copy-mode on the target; `load-buffer -b compose-<pid>`
    then `paste-buffer -p -d`; for send, after a short pause, the target's
    submit key (§5.1); append to the history file (mode 600).
  - **forward KEY:** send PgUp/PgDn/Ctrl+Home/Ctrl+End to the target.
  - Drafts: `${XDG_STATE_HOME:-~/.local/state}/dotfiles/compose/<server start
    time>-<pane id>.md`, so a restarted server never reopens another pane's
    draft.
- `configs/tmux.conf`: `bind -n M-v` runs `tmux-compose toggle "#{pane_id}"`.
- `configs/init.vim` + `configs/nvim/lua/dotfiles/prose.lua` ★ (§5.2), plus:
  with `DOTFILES_COMPOSE_TARGET` set, `Ctrl+S` (insert and normal) writes and
  sends and clears the buffer on success; `,s` stages; PgUp/PgDn/Ctrl+Home/End
  forward; the draft autosaves on change so a killed pane loses nothing.
- `tests/tmux-compose.sh` ★, with a stub `nvim`:
  - toggle creates the split with options and environment; toggling again
    moves focus both ways;
  - send to a `claude` stub logs bracketed-paste markers, the text, `^X^M`;
    `codex` logs `^I`; `opencode` logs `^X^M`; a shell gets the paste and no
    Enter;
  - dead target and empty draft fail with the draft kept;
  - no `compose-*` buffer remains and the export hook didn't fire.
- `tests/neovim.sh`: the prose layer loads only with `NVIM_PROSE`;
  `Ctrl+S` mapping only with a target; harper is enabled only when the binary
  is present.
- `README.md` compose section; `shell/shortcuts-index.tsv` rows for Alt+V,
  `Ctrl+S`, `,s`, `Ctrl+L`.

**Done when** the tests pass and the manual Phase 4 checks pass.

## Adoption and manual checks

After each phase is fast-forwarded into the live checkout:

| Phase | Adopt | Check by hand |
|---|---|---|
| 1 | `C-a r` | tmux copy, nvim yank, shell cut, and Claude copy all reach the Windows clipboard; Pause / `C-a E` toggles and the marker shows; a >64 KB copy shows the skip message |
| 2 | `bin/ai-config`; restart Claude sessions (`/tui` reports fullscreen) | drag-select in Claude copies to both destinations; clicking an inactive Claude pane only focuses it; wheel scrolls Claude |
| 3 | `C-a r`; `bin/ai-config`; new shells | Alt+S/F cross windows; ScrollLock (or `C-a v`) reviews shell, Claude, Codex, OpenCode panes; `q` returns Claude to fullscreen; `o` opens the popup; Codex pager `e`/`d`; OpenCode Ctrl+Home/End and Ctrl+Tab; prompt jumps in a shell pane |
| 4 | `./setup.sh --ai --dry-run`, then for real; `C-a r` | Alt+V opens compose under Claude, Codex and OpenCode; Ctrl+S submits without interrupting a running turn; spelling and grammar marks appear; Alt+V toggles focus |

Pending outside the repo: the keyboard firmware change (F17/F18), and whether
Windows Terminal accepts the `f17`/`f18` bindings.

## Risks

| Risk | Mitigation |
|---|---|
| A tmux behavior assumed here is wrong (key-table precedence, hook context, `copy-command` environment) | Each is pinned by a failing test first; adjust the binding, not the test |
| An agent renames a key the dispatch sends (`C-o`, `C-t`, `C-x x`, submit keys) | Stub tests document the contract; `bin/ai-config --check` and the version pins in §1 are the review points on upgrade |
| Codex rejects the pager keymap | Verified in an isolated `CODEX_HOME` before commit; drop the conflicting key |
| OpenCode V2 config schema churn | Merge only the keys listed; the V2 check gates the write |
| Prompt marks slow shell startup | Startup benchmark gate in step 3.3 |
| Large Claude dumps exceed the 50k-line history | `o`/nvim or Claude's `Ctrl+O v`; Phase 5 if it bites |
