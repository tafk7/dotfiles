# Theme system

There is one global theme, and any tmux window can override it. Everything in
a window follows that window's theme, including programs that are already
running: Neovim, fzf, bat, delta, Starship, btop, and lazygit.

```bash
theme                    # pick the global theme
theme kanagawa           # set the global theme (persists)
theme -w                 # pick a theme for this tmux window
theme -w vesper          # theme only this window
theme -w clear           # this window follows the global theme again
theme --current          # global and window themes
theme --list
theme --revert           # previous global theme
theme --window=@3 vesper # another window, by id
```

`theme` is an alias for `bin/theme-switcher`. Window themes live on the tmux
window: new panes and splits get them, and they end with the window. The
global theme is stored in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme.tsv`.

## How it works

tmux owns the colors; programs only name them.

1. **tmux styles read theme options.** Every color in `configs/tmux.conf`
   (canvas, borders, status bar, messages, copy mode) is a format such as
   `bg=#{@theme_bg}`. tmux expands these per window and draws the status bar
   from the current window.
2. **A theme is a set of tmux options.** `bin/theme-switcher` sets the
   `@theme_*` colors and `pane-colours[]` entries from `themes/<name>.sh`, on
   global window options for the global theme or on one window for `-w`.
   Ordinary tmux inheritance handles new windows, splits, and clearing; there
   are no hooks and no per-shell state.
3. **Programs use palette colors, never RGB.** `pane-colours[]` (tmux 3.3+)
   remaps the colors a program asks for, so a program that uses ANSI colors 0–15
   is recolored by the window's theme, live. Configs name roles by palette
   index:

   | Index | Role | Used by |
   |---|---|---|
   | 0–15 | the theme's ANSI colors | everything |
   | 235 | surface (cursor line, selected row) | Neovim, fzf |
   | 238 | selection | Neovim |
   | 240 | border | Neovim, fzf, delta |
   | 245 | secondary text (comments, line numbers) | Neovim, fzf, delta, Starship |
   | 22 / 28 | added line / added word background | delta, Neovim |
   | 52 / 88 | removed line / removed word background | delta, Neovim |

   Each index's standard xterm color is close to its role on a dark terminal,
   so output stays sensible where no theme applies.

| Program | Configuration |
|---|---|
| Neovim | `configs/nvim/colors/dotfiles.vim` with `notermguicolors`; Airline uses `configs/nvim/autoload/airline/themes/dotfiles.vim` |
| bat | `--theme="ansi"` in `configs/config/bat/config` |
| delta | `syntax-theme = ansi` and indexed diff styles in `configs/gitconfig` |
| fzf | indexed `--color` in `shell/fzf.sh` |
| Starship | ANSI names and a small indexed palette in `configs/starship.toml` |
| btop | the built-in TTY theme, via a copy of your `btop.conf` (`shell/tools/general.sh`) |
| lazygit | its default theme, which uses ANSI colors |

Programs that emit their own RGB colors are not recolored.

## Limits

- Inside tmux older than 3.3 there is no `pane-colours[]`: tmux's own styling
  still follows the theme, but programs use the terminal's palette.
- Outside tmux nothing changes the palette, so programs use the terminal's own
  colors. The role indices above assume a dark terminal there.
- Syntax highlighting has 16 colors, so editor and pager themes are simpler
  than the upstream truecolor ones.

## Pane tints

`pane-tint 1|2|3` gives one pane a subtler background from its window's theme;
`pane-tint 0` restores the canvas. Tints are formats, so they follow later theme
changes.

## Disabling

`dotfiles-feature disable theme` (or `setup.sh --no-theme`) resets every tmux
color to the terminal default and removes window themes. Program configs keep
using palette colors, which then come from the terminal.

`theme diagnose` prints the current themes and samples of ANSI and role colors,
drawn through the real terminal and tmux path.

## Adding a theme

Create `themes/<name>.sh` with `NAME`, `DESCRIPTION`, the `THEME_*_HEX` roles,
a 16-entry `THEME_ANSI` array, and three `THEME_TINT_*` values; copy an existing
theme for the layout. Light themes need ANSI colors dark enough to read on their
background. Then run:

```bash
python3 tests/theme-contrast.py
bash tests/theme-system.sh
theme --preview <name>
```
