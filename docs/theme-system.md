# Theme system

The theme system supports a persistent global default, tmux session themes,
tmux window themes, and group or tool overrides inside every scope. Outside
tmux, the global scope is used.

Managed tools are grouped as follows:

| Group | Tools |
|---|---|
| `code` | `vim`, `bat`, `delta` |
| `chrome` | `tmux`, `starship`, `fzf` |
| `apps` | `btop`, `lazygit` |

Available themes are discovered from `themes/`. The collection includes
Gruvbox Material Medium, Classic, Light, and Light Soft; Tokyo Night; Kanagawa
Wave and Dragon; Catppuccin Mocha and Latte; Everforest; Vesper; and the
readability-focused GitHub Light theme.

The Gruvbox family is intentionally explicit:

| Name | Editor settings | Canvas |
|---|---|---|
| `gruvbox` | Material foreground, medium background | `#282828` |
| `gruvbox-classic` | Original foreground, medium background | `#282828` |
| `gruvbox-light` | Original foreground, medium light background | `#fbf1c7` |
| `gruvbox-light-soft` | Original foreground, soft light background | `#f2e5bc` |

GitHub Light uses GitHub Primer's neutral light palette (MIT licensed) and the
maintained `projekt0n/github-nvim-theme` editor plugin. It is intentionally less
muted than the other light themes: normal text, secondary text, selected rows,
search states, and all 16 ANSI entries are checked for 4.5:1 contrast.
Existing installations should run `vplug` once to install the newly declared
editor plugin before selecting GitHub Light in Neovim.

## Resolution order

Each tool is resolved independently. The first configured value wins:

1. window tool override
2. window group override
3. window default
4. session tool override
5. session group override
6. session default
7. global tool override
8. global group override
9. global default

Scope is considered before specificity. A window default therefore supersedes
a session or global tool override. This makes a scope a complete visual context
unless a more specific value is set in that same scope.

For example:

```bash
theme-switcher tokyo-night
theme-switcher set --session default catppuccin
theme-switcher set --window default everforest
theme-switcher set --window vim gruvbox
theme-switcher set --window tmux catppuccin
```

The current window then uses Gruvbox in Neovim, Catppuccin for tmux, and
Everforest for its other tools. Other windows still inherit Catppuccin from the
session, and other sessions still inherit Tokyo Night globally.

## CLI

With no scope flag, commands operate on the global scope. This preserves the
existing global commands.

```bash
theme-switcher                         # interactive global picker
theme-switcher --session               # picker for current session default
theme-switcher --window                # picker for current window default
theme-switcher --window vim            # picker for this window's Vim override
theme-switcher -s                      # short form: current session picker
theme-switcher -w tmux                 # short form: current window tmux picker
theme-switcher kanagawa                # set global default
theme-switcher set code tokyo-night    # global group override
theme-switcher unset starship          # alias for `clear`; global compatibility
theme-switcher reset                   # clear global group/tool overrides
theme-switcher --current
theme-switcher --list
theme-switcher --revert
```

Inside tmux, bare `--session`/`-s` and `--window`/`-w` mean the current object.
Outside tmux, or when scripting, pass a stable tmux id. Quote session ids so
the shell does not expand `$`.

```bash
theme-switcher set --session default catppuccin
theme-switcher set -s code kanagawa
theme-switcher set --session='$3' code kanagawa
theme-switcher set --window default github-light
theme-switcher set -w vim gruvbox
theme-switcher set --window=@12 vim gruvbox

theme-switcher clear --window vim      # inherit window group/default, then session/global
theme-switcher clear --session default # remove the session default
theme-switcher reset --window          # remove every setting on this window
theme-switcher reset --session='$3'    # remove every setting on session $3
```

`show` displays the selected context and all effective tools. `explain` adds
the winning cascade level for each tool and can be limited to one tool.

```bash
theme-switcher show --window
theme-switcher explain --window
theme-switcher explain --session='$3' delta
```

`theme-switcher diagnose` prints default-color text, ANSI colors 0–15, and
truecolor samples in the current context. Unlike the graphical preview, this
exercises the real terminal/tmux palette path.

The interactive picker fills its preview pane with the candidate theme and
shows semantic UI states, all 16 ANSI colors, and a C++ sample rendered by that
theme's actual bat syntax definition. Moving through the list is read-only;
only Enter applies the selected theme and Escape cancels.

## State and lifetime

Global settings are written atomically to
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme.tsv` and survive shell and
machine restarts. The old checkout-local `generated/theme.sh` and
`generated/theme-overrides.sh` are read without `eval` during migration and are
never the durable source of truth.

The former active loaders `~/.tmux/theme.conf`, `~/.config/nvim/theme.vim`, and
`generated/starship.toml` are no longer read. They may remain on disk as inert
upgrade leftovers; the switcher deliberately does not delete or rewrite live
user configuration. Existing btop and lazygit files are treated as base user
configuration and receive a scoped launch overlay.

Session and window settings are tmux user options on stable ids (`$N` and
`@N`). They survive renames and window index changes because names and indexes
are never used as storage keys. Their lifetime is the tmux object:

- a new window inherits its session when the creation hook runs;
- a split inherits its window options, including the ANSI palette;
- a moved, unlinked window inherits its new session;
- a renamed session or window keeps its settings;
- killing a session/window removes its scoped settings;
- restarting the tmux server removes scoped settings unless a restoration tool
  explicitly saves and restores tmux user options.

This repository does not install tmux-resurrect or another tmux state restorer.
If one is added, include `@dotfiles_theme_*` session/window options in its saved
state. Global state remains independent and persistent.

### Linked windows

A linked window is one window object with one pane tree, even when visible in
several sessions. It cannot display conflicting canvases or expose different
environment state to the same running shell based on which client is looking
at it. The resolver therefore chooses the lowest stable linked session id as
the deterministic inheritance owner. `theme-switcher explain --window=@N`
shows all links and the owner. Set a window default when a linked window should
not inherit from that owner.

Status entries and left/right content use window-local palette values, so two
clients viewing different windows can render the selected window's colors.
Tmux messages and display-pane overlays are session options and use the session
theme; tmux does not expose those as per-client options.

## Runtime application

The switcher does not rewrite one active config for every context. It builds
immutable per-theme artifacts under
`${XDG_CACHE_HOME:-~/.cache}/dotfiles/theme/themes/<theme>/` and resolves
launch-time environment variables for each shell.

| Tool | Scoped mechanism | Existing process behavior |
|---|---|---|
| tmux | window/session options; `pane-colours[]` on tmux 3.3+ | canvas, status entries, borders, and palette update immediately |
| shell | lightweight prompt signature check | exports update at the next prompt |
| FZF | `FZF_THEME_COLORS` | next FZF invocation |
| bat | `BAT_THEME` plus one shared cache containing all custom themes | next invocation |
| Starship | per-theme `STARSHIP_CONFIG` | next prompt |
| Delta | all features loaded once; `DELTA_FEATURES` selects one per process | next Git/Delta invocation |
| Neovim | launch environment plus tracked runtime loader | new instance; use `:ThemeReload` in an existing instance |
| btop | wrapper passes scoped `--config` and `--themes-dir` | restart btop |
| lazygit | wrapper passes the user config plus a scoped theme overlay | restart lazygit |

The prompt check compares a global and tmux generation signature. If nothing
changed, it emits no exports and rebuilds no caches. Bat's cache contains every
vendored theme and is rebuilt only when a source theme changes.

`theme-switcher disable` persists the feature choice and immediately removes
theme-owned hooks and styles from a reachable tmux server without deleting
global, session, or window selections. Native defaults remain usable for every
consumer. `theme-switcher enable` rebuilds the cache and reapplies the preserved
cascade.

Outside tmux, shells, editors, and tools resolve the global cascade. No terminal
palette is changed, so standalone operation remains compatible with local and
remote terminals.

## Tmux ANSI palettes and light themes

Tmux 3.3 added the `pane-colours[]` pane option. This implementation sets the
16 ANSI entries at window scope, where existing panes inherit them and new
splits receive them automatically. Every split in a window shares that full
theme, while pane tints may vary. Different themed windows can be visible from
separate clients without changing WezTerm, another terminal, or an SSH client's
global palette. Truecolor applications continue to emit their own RGB colors,
while uncolored text uses the window foreground/background.

On tmux older than 3.3, full window foreground/background styling still works,
but tmux cannot remap ANSI colors. Light themes then depend on a compatible
terminal palette. The switcher reports `@dotfiles_theme_palette=unavailable`
and never sends OSC palette mutations, because those may leak to another tab,
session, client, or remote host. Outside tmux the same terminal-owned limitation
applies. Run `theme-switcher diagnose` to see the actual result.

Clearing a window or session setting reapplies the newly inherited palette.
No terminal-global restoration sequence is needed because the terminal palette
was never changed.

## Pane tints

`pane-tint 1`, `pane-tint 2`, and `pane-tint 3` remain subtle background
variants within a window. `pane-tint 0` or `pane-tint reset` restores the
window canvas. The tint level is stored on the pane and recomputed from the
effective tmux theme whenever that window changes. Independent full pane themes
are deliberately outside this system.

## Readability and fidelity

Normal informational text targets WCAG AA contrast of at least 4.5:1 against
its actual background. Automated checks cover the main foreground and
secondary roles, light-theme ANSI colors, tmux inactive window text, Starship
dim text, and btop inactive text. Host labels, inactive window names, comments,
line numbers, and search states use these readable roles. Pane borders and
separators may be quieter because they are decorative and are not the sole
navigation cue.

Neovim applies supported plugin setup APIs before loading each colorscheme.
Comments, line numbers, search, selection, and Airline are normalized after the
scheme loads using the theme's exact palette. The Airline adapter replaces the
former unrelated `deus` and shared `minimalist` mappings.

On a fresh machine where optional Neovim colorscheme plugins have not been
installed, startup uses Neovim's built-in default plus the selected dotfiles
palette highlights. It does not download plugins or emit `E185`. Inspect
`g:dotfiles_theme_fallback_scheme` to see which optional scheme is missing;
run `bin/install-editor-plugins` explicitly to bootstrap vim-plug and the plugins.
After that, `vplug` installs newly declared plugins and `vplugup` updates them.

Bat uses exact bundled or built-in themes. Delta 0.18.2 exposes only its
embedded bat themes and does not load the external bat cache, so exact custom
syntax themes remain unavailable there. Delta's diff chrome uses exact palette
colors; documented syntax approximations remain for Tokyo Night, Kanagawa,
Kanagawa Dragon, Everforest, Catppuccin, and Vesper. Gruvbox Material uses
Delta's `gruvbox-dark`, which is the closest embedded variant.

## Adding a complete theme

Create `themes/<name>/` with all of these files:

- `meta.sh`: display name and description
- `palette.sh`: semantic roles, a 16-entry `THEME_ANSI` array, and three pane tints
- `vim.vim`: supported setup calls before `:colorscheme`
- `shell.sh`: native bat, Starship, and Delta names
- `starship.palette.toml`
- `delta.gitconfig`
- `btop.theme`
- `lazygit.yml`
- `bat/*.tmTheme` when bat has no matching built-in

The renderer appends the theme's Starship palette to the shared template; do not
copy it into `configs/starship.toml`. Tmux styles and preview RGB values derive
from `palette.sh`. Add an editor plugin to `configs/init.vim` only when the theme
is not already supported. Then run:

```bash
bin/theme-switcher --init
tests/theme-contrast.py
tests/theme-system.sh
```

The theme is discovered automatically. Use `bin/theme-switcher --preview NAME`
for its color card and `bin/theme-switcher diagnose` inside a themed window to
check default, ANSI, and truecolor behavior together.
