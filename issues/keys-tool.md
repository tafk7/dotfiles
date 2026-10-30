# `keys`: one tool to remember, track and visualize key bindings

**Status:** design, 2026-10-29; in progress on branch `keys`.

**Core idea:** `keymap` already holds the truth: it parses every layer and traces every
chord. `cheat` has the everyday UX: a fast fzf lookup that also covers aliases and
commands. Unify them by growing keymap's build so that it also writes a flat
**entry index** (chords, intents, aliases, functions, git aliases, commands) to a
cache. One CLI, `keys`, reads that index for the shell view (fzf, plain text, a
tmux popup) and renders it into the existing page for the web view. Hand-written
rows go away. What stays curated is a small notes file, and `keys check` fails CI
when a note no longer matches the configs.

---

## 1. Survey: what to keep

### `cheat` (`bin/cheatsheet`, `shell/shortcuts-index.tsv`)

| Good, keep | Bad, fix |
|---|---|
| Instant: `fzf` over a flat file, with no build step | 383 hand-written rows that nothing checks against configs; CI (`.github/workflows/ci.yml`, "Cheatsheet TSV is well-formed") and `hooks/pre-commit` only count `│` fields. `git log` shows six commits touching the TSV just to follow key changes (`bb79e70`, `f03f030`, `de018aa`, ...) |
| Covers non-key things: 123 aliases in `shell/tools/*.sh`, WSL aliases, git aliases, `bin/` | `show_commands` reads line 2 with `sed 's/^# //'`, so Python docstrings (`keymap`, `codex-transcript`, `tmux-last-reply`) and `set -euo pipefail` (`dotfiles-feature`) vanish |
| Rows say what a key does *for the user* in context ("Alt+Z: back a turn: Claude rewind, Codex step back..."). That wording is worth migrating | `cheat commands` lists internal tmux helpers (`tmux-scroll`, `tmux-copy`, ...) alongside user CLIs |
| Category browsing (`cheat git`, `cheat tmux`) as plain text | The fzf header says "Enter: Copy command", but Enter only prints. Each run writes a heredoc preview script to `mktemp` |
| | Composite rows ("Alt+E / Alt+D") can't be linked to a binding, so nothing can tell when they go stale |
| | `cheat tools` (from `lib/registry.sh`) is about installed tools, not keys or commands |

Measured drift today: 11 aliases are defined but have no row (`bashrc`, `zshrc`,
`clean-claude-snapshots`, `vplugclean`, and others).

### `keymap` (`bin/keymap`, `lib/keymap/`)

| Good, keep (all of it) | Gaps |
|---|---|
| `sources.py` readers return `Binding` records and degrade with a `note` when a tool is missing | No descriptions beyond raw action ids and `route.FRIENDLY` labels. `defaults.py` already saves `descriptions` for OpenCode (241) and pi (90), and `sources.py` ignores them |
| `route.py` evaluates tmux `if-shell -F` per pane program and models key encodings (`KMODE_NOTE`) | Doesn't read zsh: `entry/zsh.sh` has `bindkey` lines with trailing comments |
| `analysis.py`: findings (`bug`/`adapted`/`cost`), intents, `free`, `why` | `why` prints every app even when 7 of 8 say "straight through ⇒ nothing" (try `keymap why alt+k`) |
| `known-issues.json` ratchet in CI (`tests/keymap.py`, `keymap check`) | Rebuilds from scratch on every call. `build` and `why` each take about 0.65 s (two private tmux servers and two nvim runs), too slow for a popup |
| `page.html`: keyboard, route, intents, findings, both themes, `#app=&mods=&key=` deep links | Loads Google Fonts from `fonts.googleapis.com`. viz's `FILE_CSP` allows it (`bin/viz` line 138), but the page restyles when offline |
| `defaults` keeps agent builds deterministic | Doesn't track anything: no idea of "changed since" |

**Verdict:** keymap is the engine. cheat contributes its UX ideas, its wording
(migrated once) and its non-key coverage. `bin/cheatsheet` and the TSV get deleted.

---

## 2. Data model

### 2.1 `Entry`, the one record type

New module `lib/keymap/entries.py`. It builds entries from `(data, model)` after
`analysis.build`, plus new non-key readers.

```python
@dataclass
class Entry:
    id: str            # stable key, see below
    kind: str          # chord | intent | alias | function | git-alias | command | tip
    key: str           # canonical chord 'alt+z' / 'ctrl+a z', or the name 'gs', 'viz'
    label: str         # 'Alt+Z', 'Ctrl+A Z', 'gs'
    layer: str         # windows|wezterm|tmux|tmux-prefix|tmux-copy|shell|zsh|fzf|nvim|claude|codex|opencode|pi|git|bin
    context: str = ''  # 'mode n', 'Chat', 'composer'
    summary: str = ''  # one line, the best available description
    via: str = ''      # where summary came from: note|tmux-N|comment|desc|docstring|friendly|action
    expands: str = ''  # alias body / tmux command / action id, shown in the preview
    origin: str = 'stock'   # stock | ours
    apps: dict = None  # chord rows: app -> short outcome, from traces (for "what does it do here")
    status: str = ''   # '' | bug | adapted | cost | unpressable  (from findings)
    intent: str = ''   # intent id it serves
    press: str = ''    # easy | one hand | tight | stretch | unpressable
    tags: list = ()    # 'internal', 'wsl', group names
    group: str = ''    # group id, for collapsed rows (Alt+1..0)
    source: str = ''   # 'configs/tmux.conf:303'
    changed: str = ''  # '' | added | changed | removed  (vs the baseline, section 6)
```

**Ids** must stay stable across rebuilds because notes, "seen" state and diffs key on them:
`tmux:alt+z`, `tmux-prefix:ctrl+z`, `tmux-copy:h`, `claude:alt+m@Chat`,
`nvim:ctrl+g@n`, `intent:undo-turn`, `alias:gs`, `fn:mkcd`, `git:lg`, `cmd:viz`.

Each `Binding` becomes one chord entry. tmux root bindings carry `apps`: the
per-app result, taken from the `traces` that analysis already computes. Apps
with the same outcome are merged in the display. Stock agent bindings are
entries too, but the default views hide them (section 4).

### 2.2 Derived vs curated

| Entry source | Derived from | Summary from (first that exists) |
|---|---|---|
| tmux root/prefix/copy | `list-keys` on the private server (`sources.tmux`) | **`bind -N "note"`**, read with `list-keys -N -T <table>`; else `FRIENDLY`; else the command |
| WezTerm | `wezterm-dump.lua` | trailing `-- comment` on the key line (the dump gains a line number); else the action |
| bash readline | `entry/bash.sh` + `bind -p` | trailing comment; else the humanized function name (`backward-kill-word` becomes "backward kill word") |
| zsh (**new reader**) | `bindkey` in `entry/zsh.sh` | trailing comment (already there, e.g. `# Ctrl+Right`) |
| fzf | `--bind` in `shell/fzf.sh`, `shell/tools/fzf.sh` | the action |
| Neovim | `nvim_get_keymap` (`sources.nvim`) | `desc` (already read); add `desc=` to our Lua maps |
| Claude, Codex | vendored defaults + our configs | notes; else the action id |
| OpenCode, pi | vendored defaults + our configs | **the `descriptions` already saved** in `configs/keymap/defaults/*.json` |
| aliases, functions | `shell/tools/*.sh`, `shell/platform/*.sh` (regex `^\s*alias X=`, `X() {`) | trailing `# comment`, else the comment line(s) directly above. The section header (`# Status and inspection`) becomes a tag |
| git aliases | `[alias]` in `configs/gitconfig` | the comment above; the section comment becomes a tag |
| commands | `bin/*` | Python docstring first line, else the first `#` comment after the shebang. **Never** run `--help`: some scripts have side effects |
| intents | `configs/keymap/intents.json` (add `id`) | `label` + `note` |

**Internal commands** get `tags: [internal]` and are hidden from the commands view
when they are named `tmux-*`, `compose-editor` or `git-credential-*`, or are
referenced from `configs/tmux.conf`. They still appear in the preview of the key
that runs them.

### 2.3 The curated layer: `configs/keymap/notes.toml`

TOML, read with `tomllib` (already used in `sources.codex`). It stays small, an
estimated 60–100 items against 383 rows, because most descriptions move next to
the code they describe (`bind -N`, alias comments, `desc=`).

```toml
[note."tmux:alt+z"]                  # override or add a summary to a derived entry
summary = "Back a turn: Claude rewind, Codex step back, OpenCode undo, pi session tree"

[group.window-n]                     # collapse rows in the default view
match = "tmux:alt+[0-9]"
label = "Alt+1…0"
summary = "Jump to window N"

[tip."compose-return"]               # things no config states: mouse, in-app idioms
label = ":q / :wq / :cq"
layer = "nvim"
summary = "In compose on an agent: put the draft back / keep it"
anchor = ["bin/tmux-compose", "return"]   # file + literal that must exist (drift guard)

[hide]
ids = ["tmux-prefix:ctrl+b"]
```

Rules enforced by `keys check`: every `note.*` id and `group.match` must match at
least one derived entry, and every `tip.anchor` literal must still be found in its
file. A note that no longer matches anything is exactly the drift that cheat
could never catch.

---

## 3. CLI surface

One entry point, **`bin/keys`** (Python, replacing `bin/keymap`). `keymap` stays as a
one-line shim that runs `keys "$@"` for a release, and `alias cheat=keys` stays
in `shell/tools/general.sh` for good, because it's muscle memory.

```text
keys                          interactive lookup (fzf); plain list when stdout isn't a tty or fzf is missing
keys QUERY                    same, prefilled; one exact hit prints its card instead
keys ls [FILTERS] [--tsv|--json]   plain listing (replaces cheat vim|tmux|git|shell|dev|commands|all)
keys why CHORD [APP...]       trace (keymap why), compact by default, --all for every app
keys card [APP]               a printable one-screen cheat card for a context
keys board [MODS] [--app A]   the Defy in ASCII, each key colored by its owner
keys free [MODS]              unchanged
keys diff [REV] [--since-seen] what changed in bindings, intents and findings
keys seen                     mark the current index as seen
keys quiz [APP|--changed]     flashcards (phase 4)
keys build [-o DIR]           rebuild cache + page (keymap build)
keys open [CHORD]             build if stale, then viz open, with #key=&app= deep link
keys check [--update]         CI gate, extended (section 7)
keys defaults [APP...]        unchanged, plus prints a binding diff per app
```

Filters, shared by `keys`, `ls`, `card` and `quiz`:
`-a/--app APP` (things that act in that program: its own keys, plus outer-layer
keys whose trace reaches it), `-m/--mods alt+shift`, `-k/--kind chord,alias,...`,
`-l/--layer tmux`, `-t/--tag docker`, `--ours` (the default for chords), `--stock`, `--changed`,
`--broken`.

| Old | New |
|---|---|
| `cheat` | `keys` (alias kept) |
| `cheat tmux/vim/git/shell/dev` | `keys ls -l tmux` / `-l nvim` / `-k git-alias` / `-k alias,function` / `-t docker,python,node` |
| `cheat commands` | `keys ls -k command` (internal hidden; `--all` shows them) |
| `cheat tools` | **moves out**, to `dotfiles tools` (`bin/dotfiles` already owns registry views); owner to confirm |
| `keymap *` | `keys *`, same arguments |

---

## 4. Shell UX

### 4.1 The fzf view

```text
 keys ▸ codex   [ours · alt · changed]                         Ctrl+S scope  Ctrl+T stock
  ● Alt+Z            tmux       Back a turn: Codex step back (Esc Esc)            ⟨undo-turn⟩
    Alt+M            tmux       Pick a model: runs /model from an empty prompt   ⟨pick-model⟩
  ✗ Ctrl+Shift+E     opencode   select to line end: arrives as Ctrl+E
    Ctrl+A Z         tmux pfx   Suspend the foreground program
    gs               alias      git status
    viz              command    Show charts, diagrams and HTML reports from a remote shell
┌ preview ─────────────────────────────────────────────────────────────────────────┐
│ Alt+Z   Z (left pinky) + LAlt (left thumb) · one hand · intent: Undo the last turn│
│ Claude, Codex   tmux sends Esc Esc  ⇒ rewind / edit-previous                      │
│ OpenCode        tmux sends Ctrl+X U ⇒ session.undo                                │
│ pi              straight through    ⇒ app.session.tree                            │
│ bash, fzf, Neovim, copy mode  ⇒ nothing                                           │
│ configs/tmux.conf:303 · changed in de018aa (3 days ago)                           │
└───────────────────────────────────────────────────────────────────────────────────┘
```

- **A row** has a marker (`●` changed since seen, `✗` broken, `~` rewritten on
  purpose, `·` stock), the label (18 columns), the layer (10), the summary, and the
  intent in angle brackets. Hidden tab-separated fields hold the id, kind, apps and
  tags. `--with-nth` shows only the visible columns, while `--nth` also searches
  the hidden app names and tags, so typing `codex` or `docker` narrows the list.
- **The preview** is the compact trace. Apps with identical outcomes are merged
  into one line, and apps where the chord does nothing collapse into one line at
  the end. It comes from `keys _preview ID`, which reads only `entries.json`
  (target under 80 ms). Alias and command previews show the expansion, source line,
  tags and changed status.
- **Keys inside fzf are Ctrl only.** Ctrl belongs to the pane program
  (`docs/keybindings.md`), and Alt would reach tmux first, popup or not.
  - `Enter`: copy the chord label, or the alias or command, to the clipboard
    through `bin/tmux-copy` (OSC 52, so it works over SSH), then print it. This
    finally makes the header true.
  - `Ctrl+O`: full `keys why` in the pager.
  - `Ctrl+S`: cycle scope: the app here, then all apps, then shell entries only.
  - `Ctrl+T`: show or hide stock keys.
  - `Ctrl+G`: send the alias or command to the calling pane, without Enter (popup only).
  - `Ctrl+W`: print the viz deep link.
  - `ctrl-/` and `ctrl-p` keep their meanings from `FZF_DEFAULT_OPTS` (`shell/fzf.sh`).

  Scope and stock changes use `reload(keys ls ... --tsv)` from the cache, so
  they're instant.
- Without fzf or without a tty, `keys` behaves like `keys ls`: aligned plain text,
  with color only on a tty. The pager is `less -R`.

### 4.2 tmux popup ("what does this key do here")

Two bindings in `configs/tmux.conf`. Both are free today (`keys free alt+shift`
lists `alt+shift+/` as easy, and prefix `?` is stock `list-keys`):

```tmux
bind -N "Key lookup for this pane" -n M-? display-popup -E -w 90% -h 80% \
  '"$DOTFILES_DIR/bin/keys" --here "#{pane_current_command}" --in-mode "#{pane_in_mode}" --pane "#{pane_id}"'
bind -N "Key lookup for this pane" ? display-popup -E ...same...
```

`--here` maps the command name to an app id through `route.APPS[*].cmd`
(`pane_in_mode=1` means `copy`), so the popup opens scoped to Codex when invoked
from a Codex pane. This follows the `tmux-review` popup precedent
(`bin/tmux-review:220`). Owner decision: is Alt+? (Alt+Shift, tmux's "bigger
moves") the right key, and should prefix `?` lose stock `list-keys`? With `bind -N`
everywhere, `keys` is a strictly better `list-keys`.

### 4.3 Plain views

- **`keys why`** prints compact output by default (merged identical outcomes, "nothing"
  collapsed). `--all` gives today's output.
- **`keys card codex`** fits on one 80×24 screen: intent keys first (from the intent
  table, with ✓, or the differing key), then our own bindings for that app grouped by
  tag, then recently changed ones.
- **`keys board alt --app codex`** draws the Defy's two halves from `kb.geo`
  (`lib/keymap/keyboard.py`). Each cap shows its letter, colored by the outermost
  owner using the page's layer hues mapped to 256 colors: tmux, WezTerm, Windows,
  reaches the app, or free (dim). It's the page's main view, readable over SSH.

---

## 5. Web UX

Same page (`lib/keymap/page.html`), same delivery (`keys open` writes to
`$VIZ_DIR/keymap`, and viz reloads it on rebuild). Changes:

1. **A search bar at the top** over `entries`, with the same ranking and markers as
   fzf. Picking a chord selects it on the keyboard and fills the route panel.
   Picking an alias or command opens its card. `/` focuses the bar.
2. **A new "Shell" section:** aliases, functions, git aliases and commands, grouped
   by tag in sortable tables showing expansion and source. This is where cheat's
   non-key half lives on the web.
3. **A new "What changed" section,** placed under the header when non-empty: entries
   added, changed or removed since the baseline commit (section 6), new or fixed
   findings, and per-app default changes after `keys defaults`. Changed keys get a
   ring on the keyboard.
4. **Cards:** a "Card" tab per program, rendering `keys card` in HTML with an
   `@media print` stylesheet (a one-page A4 or letter sheet).
5. **Descriptions everywhere:** the route panel and findings show `summary`, so
   users see "Back a turn" rather than only `send-keys Escape`.

**Robustness**

- Everything stays inline: data in `<script type="application/json">`, as today.
  No fetches beyond viz's own `/__viz/reload.js`.
- Drop the Google Fonts `<link>` and use the existing fallback stacks (Segoe UI and
  Cascadia Mono on the Windows client), so the page looks the same offline.
  Alternative, owner's call: inline a woff2 subset as data URIs (about 150 KB).
- Keep the tokens on `:root` with the two dark blocks, and add a three-way theme
  toggle (system, light, dark) saved in `localStorage` under try/catch.
- Size: today 683 KB, of which `traces` is 458 KB. Dedupe repeated hop arrays into a
  table and keep the page under 1 MB with entries added.
- The "seen" dismiss on the web is per-browser (`localStorage`). The authoritative
  baseline is set by `keys seen` in the shell, because viz pages can't write back.

---

## 6. Track and remember

**Snapshots.** Each build writes `entries.json` plus findings. `keys` keeps
`$XDG_STATE_HOME/keys/snapshots/<commit>.json` (keep the last 30) and
`seen.json` (the commit and a hash of the index when last marked seen).

- **`keys diff [REV]`** compares index entries by `id`: added, removed, or changed
  (summary, key, `apps` outcome, status), plus findings new or fixed. For a REV
  with no snapshot, it extracts `git archive REV` into a temp dir and runs the
  *current* `lib/keymap` against those configs. This works because every reader
  already takes `repo` as a parameter (`sources.tmux(repo, ...)`). It takes about
  1.5 s, which is fine for an explicit command.
- **Baseline for the "changed" markers:** by default the `seen.json` commit, with
  `--since REV|7d` as overrides. When the index differs from what was seen, the
  plain `keys` header shows "12 changed since you last looked: Ctrl+R to list".
- **Agent upgrades:** `keys defaults` prints a per-app diff of stock bindings
  (added, removed, rebound) and then runs check. `bin/ai-update` should call it
  (owner decision: automatically or as a printed hint). Together with the
  known-issues ratchet, "keys an agent upgrade broke" becomes a concrete list.

**Remember**, in order of value:

1. **Changed markers and the What changed section.** Cheap, and they target exactly
   the keys you're likely to fumble this week.
2. **Context cards** (`keys card`, the web Card tab). Printing one per agent is the
   realistic learning aid.
3. **Popup scoped to the current pane.** Lookup in the moment beats memorization.
4. **`keys quiz`** (phase 4, optional, about 150 lines). The summary is the prompt,
   and you type the chord as text (`alt+z`). Real keystrokes can't be captured,
   because tmux eats Alt. Multiple choice is the fallback. Leitner boxes are kept in
   `$XDG_STATE_HOME/keys/quiz.json`, weighted to changed entries, intents and `ours`.
   Skip it if the cards are enough.

Not recommended: tips in the status line or at shell start. They add noise and
cost startup time (`tests/startup-benchmark-test.py`).

---

## 7. Testing, CI, performance

**`keys check`** (CI, replaces the TSV awk step in `ci.yml` and `hooks/pre-commit`):

1. Known broken keys: unchanged ratchet (`configs/keymap/known-issues.json`).
2. Notes integrity: every `note`/`group`/`hide` id resolves, and every `tip.anchor` is found.
3. **A description ratchet:** the count of `origin=ours` entries whose `via` is
   `action` or `friendly` (no real description) must not grow. It's stored in
   `known-issues.json` as `undescribed: N`. New tmux bindings without `-N` fail CI.
4. Every non-internal `bin/*` has a docstring or header comment. This would have
   caught the four commands cheat drops.
5. Intents: every `intents.json` row has an `id`, and `apps` names known app ids.

**`tests/keymap.py`** gains fixtures: an alias with a comment above, one with a
trailing comment, a docstring script, a `set -e` script, `bind -N` parsing, zsh
`bindkey`, id stability (build twice and compare ids), `keys diff` over two fixture
trees, and `--here` mapping. Also a golden test for the `keys ls --tsv` columns.

**Performance targets and how to meet them**

| Path | Target | How |
|---|---|---|
| `keys` / popup to first paint | < 150 ms | fzf reads `$XDG_CACHE_HOME/keys/index.tsv` directly. The staleness check runs in bash: `find <inputs> -newer stamp -print -quit`, measured at 18 ms |
| preview | < 80 ms | `keys _preview ID` loads `entries.json` (a few hundred KB) instead of `keymap.json` (632 KB, 110 ms with Python startup) |
| stale cache | never blocks | show the old index with a "rebuilding…" header and run `keys build` in the background, then `reload` |
| `keys build` | ≤ 1 s | today 0.65 s. Readers already run in sequence, so the tmux dumps and nvim runs could run in parallel if needed |

The input list for staleness (`configs/{tmux.conf,wezterm.lua,init.vim,gitconfig}`,
`configs/nvim`, `configs/keymap`, `configs/ai`, `configs/{codex,opencode}*`,
`entry/`, `shell/`, `bin/`, `lib/keymap`) lives in one place, `keys inputs`, which
both the bash fast path and Python use. The cache key also includes the commit, so
switching branches or worktrees never shows the wrong index.

---

## 8. Phases

| Phase | Scope | Effort |
|---|---|---|
| **1. Index and cache** | `entries.py`, non-key readers (aliases, functions, git, bin, zsh), OpenCode and pi descriptions, `bind -N` reading, ids, cache and stamp, `keys ls/why/build/check` (rules 2–5), `bin/keys` + `keymap` shim | 2–3 days |
| **2. Migrate and switch** | One-off script (in `maintenance/`, deleted after) that matches the 383 TSV rows to entries. Alias and function wording becomes source comments, tmux wording becomes `bind -N`, intent-level wording goes in `notes.toml`, leftovers become `tip`s. Review the diff. Delete `bin/cheatsheet`, the TSV and its CI and hook steps; update `README.md:110`, `docs/customization.md:121-126`, `docs/keybindings.md` | 1–2 days (mostly review of wording) |
| **3. Shell UX** | fzf view, preview, Ctrl binds, popup + `--here`, `card`, `board` | 2 days |
| **4. Web** | search bar, Shell section, What changed, Cards, fonts offline, theme toggle, trace dedupe | 2–3 days |
| **5. Track and remember** | snapshots, `diff`, `seen`, defaults diff, `ai-update` hook; then optional `quiz` | 1–2 days, +1 for quiz |

Phases 1–2 alone remove the drift. Ship them first, keeping cheat's current UI
running on the generated TSV, so the switch is invisible.

**Risks**

- `bind -N` changes the `list-keys` output format. The regex in `sources.tmux_dump`
  (`bind-key\s+(?:-r\s+)?-T`) may need to accept `-N "..."`. Verify on tmux 3.4, 3.7
  and 3.8 (the versions `issues/intent-keys.md` was tested on).
- Id churn when a tmux binding moves between tables, or a Claude context is renamed
  upstream. The diff shows it as remove plus add, which is acceptable.
- The comment-above heuristic picks up section prose. Limit it to one or two lines
  directly adjacent, and let the description ratchet expose gaps.
- Wording migration is judgment work. Some cheat rows are better than anything
  derivable, and those rightly become notes.
- The popup inherits tmux's key handling. Verify that Ctrl binds reach fzf inside
  `display-popup` on 3.4.

**Open questions for the owner**

1. Name: `keys` (my pick; `keymap` stays as a shim) or keep `keymap` as the only name?
2. Popup keys: Alt+? and prefix `?` (which replaces stock `list-keys`)?
3. Should every tmux binding get a `bind -N` note? It's the best derivable source and
   also improves native `list-keys -N`, but it touches about 250 lines of `tmux.conf`.
4. Fonts: system stacks only, or inline woff2?
5. Should `cheat tools` move to `dotfiles tools`, or be dropped?
6. Should stock agent keys be searchable by default, or only behind Ctrl+T or `--stock`?
7. Should `keys defaults` run from `ai-update` automatically?
8. Is the quiz worth building, or are cards and changed markers enough?
