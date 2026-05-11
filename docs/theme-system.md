# Theme System Documentation

The dotfiles theme system applies a single color scheme across **neovim, tmux,
shell (FZF + prompt), bat, starship, delta, btop, and lazygit** with one
command. Themes are auto-discovered from `themes/` — no central registry to
update when adding one.

## Overview

The theme system lets you:

- Switch between multiple color schemes instantly across every tool.
- Preview themes before applying them.
- Maintain consistent colors across all terminal applications.
- Add new themes by dropping a directory under `themes/`.

## Available Themes

Themes are discovered from `themes/<name>/`. Out of the box:

| Theme              | Best For              | Vibe                                  |
| ------------------ | --------------------- | ------------------------------------- |
| **gruvbox**        | Retro feel            | Warm, comfortable, nostalgic (default) |
| **nord**           | Long coding sessions  | Cool, professional, Arctic            |
| **tokyo-night**    | Modern development    | Vibrant, city lights, contemporary    |
| **kanagawa**       | Focused work          | Earthy, Japanese aesthetic, calming   |
| **catppuccin**     | Gentle on eyes        | Soft pastels, cozy, smooth (Mocha variant) |

## Usage

### Quick Start

```bash
# Interactive selection (FZF picker, with preview)
bin/theme-switcher

# Direct switch
bin/theme-switcher nord
bin/theme-switcher tokyo-night

# Show current theme
bin/theme-switcher --current

# List available themes
bin/theme-switcher --list

# Preview without applying
bin/theme-switcher --preview kanagawa

# Revert to the previous theme
bin/theme-switcher --revert
```

### Per-Component Overrides

Sometimes you want a mix — say, a Tokyo Night editor on a Kanagawa terminal
chrome. The switcher supports a CSS-style cascade across three groups:

| Group     | Surfaces                | Coupling reason                          |
|-----------|-------------------------|------------------------------------------|
| `code`    | `vim`, `bat`, `delta`   | Share the screen during edit/diff/preview |
| `chrome`  | `tmux`, `starship`, `fzf` | Persistent UI elements visible together |
| `apps`    | `btop`, `lazygit`       | Full-screen TUI takeovers                |

**Cascade rule:** `surface override > group override > global default`.

```bash
# Group override — flip just the editor stack
bin/theme-switcher set code tokyo-night

# Surface override — flip just one surface
bin/theme-switcher set starship nord
bin/theme-switcher set chrome.starship nord   # equivalent qualified form

# See what's effective everywhere
bin/theme-switcher show

# Remove one override (cascades back to group/global)
bin/theme-switcher unset starship

# Clear every override (back to pure global)
bin/theme-switcher reset
```

Example `theme-switcher show` output:

```
global: catppuccin
├─ code   : tokyo-night  (override)
│  ├─ vim     : tokyo-night
│  ├─ bat     : tokyo-night
│  └─ delta   : tokyo-night
├─ chrome : catppuccin
│  ├─ tmux    : catppuccin
│  ├─ starship: nord  (override)
│  └─ fzf     : catppuccin
└─ apps   : catppuccin
   ├─ btop    : catppuccin
   └─ lazygit : catppuccin
```

Overrides are stored in `generated/theme-overrides.sh` (gitignored).
Bare `bin/theme-switcher <name>` only updates the global default — your
overrides survive theme switches. Use `reset` first if you want a clean slate.

Caveats:

- `delta`, `btop`, and `lazygit` configs are machine-global, so the
  override is honored but only one theme of each can be live per machine.
- Open `nvim` sessions need `:source ~/.config/nvim/theme.vim` to repaint.
- `bin/verify` summarizes the effective cascade and warns on artifact mismatch.

### How It Works

When you switch themes, `bin/theme-switcher` writes / regenerates the
following loader files. The originals in `themes/<name>/` are never modified.

| Surface  | Loader / target                             | Mechanism                                   |
| -------- | ------------------------------------------- | ------------------------------------------- |
| Neovim   | `~/.config/nvim/theme.vim`                  | Sources `themes/$THEME/vim.vim` at runtime  |
| Tmux     | `~/.tmux/theme.conf`                        | Sources `themes/$THEME/tmux.conf` at runtime |
| Shell    | `generated/theme.sh`                        | Exports `DOTFILES_THEME`, sources theme's `shell.sh` |
| Bat      | `BAT_THEME` (via shell.sh) + `bat/*.tmTheme` | Vendored `.tmTheme` + bat cache rebuild    |
| Starship | `generated/starship.toml`                   | Concatenates base config + active palette   |
| Delta    | `generated/delta.gitconfig`                 | Included by `~/.gitconfig`                  |
| Btop     | `~/.config/btop/themes/dotfiles-<name>.theme` + `btop.conf` patch | Drop-in theme + `color_theme = "dotfiles-<name>"` |
| Lazygit  | `~/.config/lazygit/config.yml` (marker block) | Marker block keeps user content intact     |

The active theme name and previous-theme name are stored inside
`generated/theme.sh` (so `--revert` works across sessions).

### Integration Points

#### Neovim

- Theme loaded from `~/.config/nvim/theme.vim` (auto-generated).
- Falls back to gruvbox-material if no theme is set.
- All theme plugins are pre-installed via vim-plug.
- Airline theme updates automatically.

#### Tmux

- Theme loaded from `~/.tmux/theme.conf` (auto-generated).
- Includes status bar styling and pane borders.
- After switching, run `Ctrl-a r` to reload, or fully restart tmux.

#### Shell (Bash/Zsh)

- Colors loaded from `generated/theme.sh`.
- Affects FZF colors, prompt accents, error/success symbols.
- New shells pick up the theme automatically; for the current shell, `reload`.

#### FZF

- Each theme defines `FZF_THEME_COLORS` in its `shell.sh`.
- Affects fuzzy finder appearance everywhere FZF is used.

#### Bat

- Each theme exports `BAT_THEME` from its `shell.sh`.
- Themes that aren't bat built-ins ship a vendored `.tmTheme` under
  `themes/<name>/bat/<name>.tmTheme`.
- `bin/theme-switcher` rebuilds the bat cache only when the vendored set changes.

#### Starship

- A single `configs/starship.toml` defines structure and references colors via
  `palette = "$STARSHIP_PALETTE"`.
- Each theme contributes a `themes/<name>/starship.palette.toml` snippet
  containing one `[palettes.<name>]` block.
- The switcher concatenates base + active palette into
  `generated/starship.toml` and points `STARSHIP_CONFIG` there.

#### Delta (git diff)

- Each theme provides `themes/<name>/delta.gitconfig` with a `[delta]`
  block (syntax-theme + plus/minus styles).
- The switcher writes the active one to `generated/delta.gitconfig`,
  which is included by `~/.gitconfig`.

#### Btop

- Each theme ships a `themes/<name>/btop.theme`.
- The switcher copies it to `~/.config/btop/themes/dotfiles-<name>.theme`
  and patches `~/.config/btop/btop.conf` (`color_theme = "dotfiles-<name>"`).

#### Lazygit

- Each theme provides `themes/<name>/lazygit.yml` (a `gui.theme:` block).
- The switcher merges it into `~/.config/lazygit/config.yml` between
  `# >>> dotfiles theme >>>` / `# <<< dotfiles theme <<<` markers, so any
  user customizations outside the block survive.

## Adding a New Theme

1. Create the directory:
   ```bash
   mkdir -p themes/my-theme/bat
   ```

2. Create the **required** files:

   **`meta.sh`** — name + description (one line each):
   ```bash
   NAME="My Theme"
   DESCRIPTION="One-line summary for the picker"
   ```

   **`vim.vim`** — neovim colorscheme:
   ```vim
   try
       colorscheme my-theme
       let g:airline_theme = 'my_theme'
   catch
       colorscheme desert
   endtry
   ```

   **`tmux.conf`** — status bar styling (status-style, pane-border-style, …).

   **`shell.sh`** — exports for FZF + bat:
   ```bash
   export FZF_THEME_COLORS='--color=bg+:#…,bg:#…,fg:#…,…'
   export BAT_THEME='my-theme'
   ```

   **`colors.sh`** — RGB triplets used by `--preview`:
   ```bash
   export THEME_BG_R=30 THEME_BG_G=30 THEME_BG_B=30
   export THEME_FG_R=220 THEME_FG_G=220 THEME_FG_B=220
   export THEME_PRIMARY_R=… THEME_PRIMARY_G=… THEME_PRIMARY_B=…
   export THEME_SECONDARY_R=… THEME_SECONDARY_G=… THEME_SECONDARY_B=…
   export THEME_TINT_1='#…' THEME_TINT_2='#…' THEME_TINT_3='#…'
   ```

3. Create the **optional** per-tool palette files. Each is a no-op when
   missing — the switcher logs a warning and skips that surface.

   - `bat/my-theme.tmTheme` — Sublime/TextMate `.tmTheme` (omit if `BAT_THEME`
     points at a bat built-in like `gruvbox-dark` or `Nord`).
   - `starship.palette.toml` — single `[palettes.my-theme]` block.
   - `delta.gitconfig` — single `[delta]` block (or `[delta "my-theme"]`
     plus `features = my-theme` in the active block).
   - `btop.theme` — drop-in btop theme.
   - `lazygit.yml` — `gui.theme:` block.

4. Install vim plugin (if needed) by adding to `configs/init.vim`:
   ```vim
   Plug 'author/my-theme.vim'
   ```

5. Apply:
   ```bash
   bin/theme-switcher my-theme
   ```

The theme is discovered automatically — no central registry to update.

## Troubleshooting

### Theme not applying in neovim
- Run `:PlugInstall` to ensure the theme plugin is installed.
- Check `:colorscheme` to see what's currently active.
- Verify `~/.config/nvim/theme.vim` exists and is readable.

### Tmux colors not updating
- Reload tmux config: `Ctrl-a r`.
- For full update: exit and restart tmux.

### Shell prompt colors not changing
- Run `reload` (or `source ~/.bashrc` / `source ~/.zshrc`).
- Start a new shell session.

### FZF colors not updating
- FZF colors load when FZF starts — try a new FZF command or restart shell.

### Bat colors not updating
- Run `bat cache --build` once after switching to refresh.
- Check `bat --list-themes` to confirm the theme is known.

### Starship colors not updating
- Confirm `STARSHIP_CONFIG` points at `generated/starship.toml`.
- Check that `generated/starship.toml` exists and contains
  `[palettes.<your-theme>]`.

### Lazygit colors not updating
- Open `~/.config/lazygit/config.yml` and confirm the
  `# >>> dotfiles theme >>>` block reflects the current theme.
- Restart lazygit (it reads config at start).

## Technical Details

### File Structure

```
themes/
├── nord/
│   ├── meta.sh                    # required
│   ├── vim.vim                    # required
│   ├── tmux.conf                  # required
│   ├── shell.sh                   # required (FZF + BAT_THEME)
│   ├── colors.sh                  # required (RGB for preview)
│   ├── bat/nord.tmTheme           # optional
│   ├── starship.palette.toml      # optional
│   ├── delta.gitconfig            # optional
│   ├── btop.theme                 # optional
│   └── lazygit.yml                # optional
├── kanagawa/
│   └── ...
└── ...

bin/
└── theme-switcher                 # the orchestrator

generated/
├── theme.sh                       # current theme + previous theme
├── starship.toml                  # base + active palette (concatenated)
└── delta.gitconfig                # active delta block
```

### Configuration Paths

- **Active theme name**: stored as `DOTFILES_THEME=...` in `generated/theme.sh`.
- **Previous theme**: stored as `_DOTFILES_PREVIOUS_THEME=...` in same file.
- **Vim loader**: `~/.config/nvim/theme.vim`.
- **Tmux loader**: `~/.tmux/theme.conf`.
- **Bat tmTheme**: copied to bat config dir and cache rebuilt.
- **Starship config**: `generated/starship.toml` (pointed at by `STARSHIP_CONFIG`).
- **Delta config**: `generated/delta.gitconfig` (included by `~/.gitconfig`).
- **Btop**: `~/.config/btop/themes/dotfiles-<name>.theme` + `btop.conf` patch.
- **Lazygit**: marker block inside `~/.config/lazygit/config.yml`.

### Dependencies

- `fzf` — interactive theme picker.
- `tput` — terminal color preview.
- Standard unix tools: `ln`, `mkdir`, `sed`, `awk`.

## Tips

- **Quick alias**:
  ```bash
  alias nord='bin/theme-switcher nord'
  alias tokyo='bin/theme-switcher tokyo-night'
  ```

- **Per-project override**: set `DOTFILES_THEME` in a project's `.envrc` and
  source `themes/$DOTFILES_THEME/shell.sh` from there.

## Quick Start (10-Second Version)

```bash
bin/theme-switcher                 # interactive (FZF)
bin/theme-switcher nord            # apply nord
bin/theme-switcher --revert        # back to previous
bin/theme-switcher --list          # show all
```

After switching:

- **Tmux**: `Ctrl-a r` to reload.
- **Vim**: applies to new sessions.
- **Shell**: applies to new terminals; `reload` for current.
