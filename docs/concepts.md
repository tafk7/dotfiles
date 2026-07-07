# Dotfiles Concepts

A one-page mental model that ties together the four pillars of this repo.
Read this first — every other doc assumes you understand these primitives.

```
                          ┌──────────────────────────────────┐
                          │           setup.sh               │
                          │   (chooses tier, runs phases)    │
                          └────────┬─────────────────────────┘
                                   │ reads
                ┌──────────────────┼──────────────────────┐
                │                  │                      │
        ┌───────▼───────┐  ┌───────▼───────┐    ┌─────────▼─────────┐
        │  CONFIG_MAP   │  │  TOOL_*       │    │   PACKAGES        │
        │  (config.sh)  │  │  (registry.sh)│    │   (config.sh)     │
        │               │  │               │    │                   │
        │ "what files   │  │ "what tools   │    │ "what apt groups  │
        │ get linked    │  │ get installed │    │ get installed for │
        │ where"        │  │ at each tier" │    │ each tier"        │
        └───────┬───────┘  └───────┬───────┘    └───────────────────┘
                │                  │
                ▼                  ▼
        symlinks in $HOME    binaries in ~/.local/bin
                │                  │
                └─────────┬────────┘
                          ▼
                ┌───────────────────────┐
                │  shell/init.sh        │
                │  (sourced by ~/.bashrc│
                │   and ~/.zshrc)       │
                └───────────┬───────────┘
                            │ sources
                ┌───────────┴───────────┐
                ▼                       ▼
        shell/env.sh            generated/theme.sh
        (PATH, exports)         (active palette → BAT_THEME,
                                 STARSHIP_PALETTE, FZF colors,
                                 DELTA_FEATURE, etc.)
```

## The four pillars

### 1. Tiers — *how much* gets installed

Defined by the `--config | --shell | --dev | --work` flag to `setup.sh`. Each
tier includes everything from the previous tier:

| Tier | What it adds | Sudo? |
|------|--------------|-------|
| `config` | Symlinks only | No |
| `shell`  | Modern CLI tools (eget + apt: starship, eza, fzf, zoxide, delta, btop, glow, lazygit, uv, bat, fd, ripgrep, direnv, sd) | Yes |
| `dev`    | neovim, tmux, plantuml | Yes |
| `work`   | NVM, Docker, Azure CLI | Yes |

Three extras sit outside the cumulative chain:

- `--ai` — an **orthogonal** flag that installs the AI CLIs (Claude Code,
  Codex) into `~/.local/bin`. It combines with any tier and is off by default,
  so a machine whose org manages the AI install can run `--work` (or any tier)
  without a competing copy. The shell aliases load regardless of this flag.
- `--rdp` — an **orthogonal** flag that installs and configures the xrdp RDP
  server with an XFCE session (see `issues/xrdp-remote-desktop.md`). Opt-in per
  machine and deliberately NOT implied by `--full`: no tier should silently
  open a network listener.
- `--full` — shorthand for `--work --ai` (everything except `--rdp`).

Tier membership is data, not code. Each tool's tier lives in
`TOOL_TIER` in `lib/registry.sh` (the AI CLIs use the `ai` tier value; xrdp
uses `rdp`). To move a tool between tiers, edit that table — no other change
required.

### 2. CONFIG_MAP — *what* gets symlinked

`lib/config.sh` declares one map:

```bash
declare -A CONFIG_MAP=(
    [tmux.conf]="$HOME/.tmux.conf:symlink"
    [gitconfig]="$HOME/.gitconfig:gitconfig"     # special: template-processed
    ...
)
```

Each key is a source filename; each value is `<target>:<type>`. The source path
is resolved by `config_source_path()` (`entry/` for shell rc files, `configs/`
for everything else). At install time, `setup.sh` walks the map and creates the
symlinks. At verify time, `bin/verify` walks it and checks them. At drift-check
time, `bin/diff-config` walks it too. **Three tools, one source of truth.**

### 3. Tool registry — *which* binaries to install / verify / remove

`lib/registry.sh` declares parallel arrays keyed by tool short-name:

```bash
TOOL_BINARY[fzf]=fzf            # what to look for in PATH
TOOL_METHOD[fzf]=eget           # how it gets installed (eget|apt|installer)
TOOL_TIER[fzf]=shell            # min tier that installs it
TOOL_PATHS[fzf]=...             # paths to delete on uninstall (eget falls back to ~/.local/bin/<binary>)
TOOL_VERIFY[fzf]=...            # custom verify command (optional)
```

Adding a new tool means adding one row to each array (and an `eget.toml` block
or an `installers/install-<tool>.sh` script). The four tools that read this
registry —`setup.sh`, `bin/verify`, `bin/uninstall-tool`, `bin/cheatsheet
tools` — pick it up automatically.

### 4. Theme cascade — *how* themes apply to many surfaces

`bin/theme-switcher` resolves a single `<surface, theme>` decision through a
three-level cascade: **surface override → group override → global default**.

```
DOTFILES_THEME           = nord            ← global (set once)
DOTFILES_THEME_CODE      = tokyo-night     ← group override (vim, bat, delta)
DOTFILES_THEME_STARSHIP  = catppuccin      ← surface override (just starship)
```

**Three groups, eight surfaces** (defined in `lib/theme-resolve.sh`):

| Group   | Surfaces                  |
|---------|---------------------------|
| code    | vim, bat, delta           |
| chrome  | tmux, starship, fzf       |
| apps    | btop, lazygit             |

Surfaces are **globally unique**, so `theme set fzf nord` works just as well
as the (no longer accepted) qualified form. `theme show` prints the entire
resolved cascade tree.

Themes themselves are **data on disk**: each `themes/<name>/` directory
contains per-tool palette files (`vim.vim`, `tmux.conf`, `starship.palette.toml`,
`btop.theme`, etc.). `theme-switcher` writes the resolved active artifacts to
`generated/` (gitignored), and `shell/env.sh` exports the right env vars from
`generated/theme.sh` so each tool finds its themed config.

## File layout cheat sheet

```
setup.sh                  → orchestrator (3 phases × 4 tiers)
lib/
  config.sh               → CONFIG_MAP + PACKAGES (data, no side effects)
  registry.sh             → TOOL_* arrays (data, no side effects)
  install.sh              → install-time helpers (apt, eget, run_installer)
  runtime.sh              → safe-everywhere helpers (log, is_wsl, command_exists)
  theme-resolve.sh        → cascade resolution + override file I/O
configs/                  → symlink sources (target == ~/.<file>)
entry/                    → ~/.bashrc, ~/.zshrc, ~/.profile sources
shell/
  init.sh                 → shared init for bash + zsh
  env.sh                  → PATH composition + static exports
  tools/*.sh              → domain-split aliases & functions
themes/<name>/            → per-tool palette files
installers/install-*.sh   → one script per non-eget tool
eget.toml                 → static binary downloads (versions pinned)
generated/                → runtime artifacts (gitignored)
bin/
  theme-switcher          → 5 themes × 8 surfaces × 3 groups (cascade)
  verify                  → 44 health checks across configs + tools + theme
  cheatsheet              → searchable shortcut catalog (incl. tools from registry)
  diff-config             → drift report between configs/ and ~/
  check-updates           → eget.toml pins vs latest GitHub releases
  uninstall-tool          → removes tools by registry method
  replace                 → rg + sd find/replace (alias: fr)
docs/
  concepts.md             → this file
  architecture.md         → boundary rules + sourcing order
  customization.md        → "how to add X" recipes
  theme-system.md         → cascade internals + adding themes
```

## How a single change propagates

A worked example: **adding a new tool `helix`**.

1. Add a row to each array in `lib/registry.sh`:
   ```bash
   TOOL_BINARY[helix]=hx
   TOOL_METHOD[helix]=eget
   TOOL_TIER[helix]=dev
   ```
2. Add a release block to `eget.toml`.
3. Run `./setup.sh --dev` (or `eget --download-all`).

That's it. **All of these update automatically:**

- `bin/verify` now checks for `hx` on PATH.
- `bin/uninstall-tool helix` knows how to remove it (eget → `~/.local/bin/hx`).
- `bin/uninstall-tool --list` lists it under tier `dev`.
- `bin/cheatsheet tools` shows it under "Tier: dev".

This data-driven design is the whole point. **Changes happen in tables, not
code.**

## Where to go next

- `docs/architecture.md` — boundary rules for which `lib/` file belongs where.
- `docs/customization.md` — recipes for adding APT packages, configs, aliases.
- `docs/theme-system.md` — full theme model (cascade, overrides, surfaces).
- `docs/THEME_QUICK_START.md` — picker UI + day-to-day commands.
