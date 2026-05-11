# Dotfiles — Ubuntu Development Environment

Tiered dotfiles system for Ubuntu/WSL. Install only what you need: from config-only (no sudo) to complete development environment.

## Quick Start

```bash
./setup.sh --config              # Symlinks only (no sudo)
./setup.sh --shell               # + starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, direnv
./setup.sh --dev                 # + neovim, lazygit, tmux
./setup.sh --full                # + NVM, pyenv, uv, poetry, Docker, Azure CLI
./setup.sh --shell --dry-run     # Preview without changes
```

Each tier includes all previous tiers. Use `--force` to overwrite without prompting.

After installation, verify with `./bin/verify` and restart your shell.

## What You Get

### Modern CLI Replacements

| Classic | Modern | Alias |
|---------|--------|-------|
| `ls` | eza | `ll`, `la`, `l`, `tree` |
| `cat` | bat | `view` |
| `find` | fd | — |
| `grep` | ripgrep | — |
| `cd` | zoxide | `z`, `zi` |
| `diff` | delta | (auto via git) |
| `top` | btop | `top` |

### Shell & Navigation

```bash
reload                    # Reload shell configuration
mkcd <dir>                # Create directory and cd into it
proj                      # Interactive project finder (FZF)
psg <name>                # Search running processes
extract <archive>         # Universal archive extraction
```

### Git

```bash
# Aliases (g + command abbreviation)
gs / ga / gc / gd         # status / add / commit / diff
gsw / gswc / gb           # switch / switch -c / branch
gp / gpl / gf             # push / pull / fetch
gst / gstp                # stash / stash pop
lg                        # lazygit TUI

# FZF-enhanced (f prefix)
fgb                       # Interactive branch switcher
fgl                       # Interactive commit browser
frg                       # Interactive ripgrep search
```

### Python

```bash
pyset 3.11.9              # Set project Python + create .venv
pyset --default 3.11.9    # Set global default
vactivate                 # Manual venv activation
pyinfo                    # Show environment info
pylist                    # List installed versions

# uv shortcuts
uvs / uvr / uva / uvpi    # sync / run / add / pip install

# direnv auto-activation (recommended)
echo 'layout pyenv 3.11.9' > .envrc && direnv allow
```

### VS Code

```bash
c                         # Open current directory
cf                        # FZF file search → open in VS Code
cproj                     # FZF project search → open in VS Code
cdiff <a> <b>             # Diff two files in VS Code
```

### Docker

```bash
dps / dpsa                # ps / ps -a
dc / dcu / dcd / dcl      # compose / up -d / down / logs
denter <id>               # Exec into container (bash or sh)
dstopall                  # Stop all running containers
```

### Node.js

```bash
ni / nr / nrd / nrb       # install / run / run dev / run build
nclean                    # rm node_modules + reinstall
```

### Tmux

```bash
tm <name> / ta <name>     # New session / attach
tl / tk <name>            # List / kill session
```

Clipboard: copy-mode `y` and `<prefix> P` auto-detect WSL (`clip.exe` /
`powershell.exe Get-Clipboard`), Wayland (`wl-copy` / `wl-paste`), or X11
(`xclip`). OSC 52 (`set-clipboard on`) handles SSH sessions.

### WSL (auto-detected)

```bash
pbcopy / pbpaste          # Clipboard integration
sync-ssh                  # Import SSH keys from Windows
cdwin / cddesk / cddl     # Navigate to Windows directories
open / explorer           # Open in Windows Explorer
```

## Theme System

Five unified themes applied across **eight surfaces** with a single command:
neovim, tmux, shell (FZF colors + env exports), bat, starship, delta, btop,
and lazygit.

```bash
./bin/theme-switcher              # Interactive FZF selection
./bin/theme-switcher nord         # Direct switch
./bin/theme-switcher --preview tokyo-night
./bin/theme-switcher --revert     # Revert to previous
./bin/theme-switcher --list       # Show available themes
./bin/theme-switcher --init       # Re-render all surfaces from current theme
```

**Per-component overrides** (CSS-style cascade — `surface > group > global`):

```bash
./bin/theme-switcher set code tokyo-night       # editor group → tokyo-night
./bin/theme-switcher set starship nord          # just starship → nord
./bin/theme-switcher set chrome.starship nord   # qualified form, same thing
./bin/theme-switcher show                       # see the full cascade tree
./bin/theme-switcher unset starship             # back to chrome group/global
./bin/theme-switcher reset                      # clear all overrides
```

Groups: `code` (vim, bat, delta) · `chrome` (tmux, starship, fzf) ·
`apps` (btop, lazygit). See [docs/theme-system.md](docs/theme-system.md#per-component-overrides).

**Available:** Nord, Kanagawa, Tokyo Night, Gruvbox Material, Catppuccin Mocha

Per-tool palettes live under `themes/<name>/`:

| File                          | Consumer                                  |
|-------------------------------|-------------------------------------------|
| `meta.sh`                     | Theme metadata (display name, description)|
| `colors.sh`                   | Canonical hex/RGB palette                 |
| `vim.vim`                     | Neovim/vim colorscheme + overrides        |
| `tmux.conf`                   | tmux status bar + pane borders            |
| `shell.sh`                    | FZF colors + `BAT_THEME`/`STARSHIP_PALETTE`/`DELTA_FEATURE` exports |
| `starship.palette.toml`       | Starship `[palettes.<name>]` block        |
| `delta.gitconfig`             | Delta `[delta "<name>"]` feature          |
| `btop.theme`                  | btop color theme                          |
| `lazygit.yml`                 | lazygit `gui.theme` block                 |
| `bat/<name>.tmTheme` (opt.)   | bat tmTheme — only when not a bat builtin |

Generated artifacts live in `generated/` (gitignored):
`theme.sh`, `starship.toml`, `delta.gitconfig`, `bat/cache/`. The bat cache
is **isolated** (`BAT_CACHE_PATH`) so it doesn't pollute delta's embedded
bat (different versions are binary-incompatible).

## Architecture

```
setup.sh                  Entry point — 3-phase orchestrator (reads lib/config.sh)
lib/
  install.sh              Install-time helpers (APT, backup, eget, tier functions)
  runtime.sh              Runtime helpers (logging, is_wsl, command_exists)
  config.sh               Declarative data: CONFIG_MAP + PACKAGES
  registry.sh             Tool registry: TOOL_BINARY/METHOD/TIER/PATHS for verify + bin/cheatsheet
configs/                  Config files without dots (symlinked to ~/.<name>)
themes/                   5 theme dirs — see "Theme System" table above
shell/
  init.sh                 Single sourcing sequence for bash + zsh
  bash.sh / zsh.sh        Shell-specific entry → ~/.bashrc / ~/.zshrc
  profile.sh              Login shell → ~/.profile
  env.sh                  Environment: PATH, EDITOR, PROJECTS_DIRS, BAT_CACHE_PATH, STARSHIP_CONFIG, theme exports
  fzf.sh / tool-init.sh   Tool initializers (zoxide, starship, fzf keybinds)
  tools/*.sh              Domain-split functions + aliases (nav, process, python, fzf, vscode, claude, docker, git, node, tmux, vim, general)
  platform/wsl.sh         WSL-only helpers (pbcopy/pbpaste, sync-ssh, cdwin)
  lazy/nvm.sh             Lazy NVM loader
installers/               Per-tool install scripts (run by lib/install.sh::run_installer)
generated/                Theme artifacts + bridge.sh (gitignored)
bin/                      User commands (theme-switcher, verify, cheatsheet, replace)
eget.toml                 Static binary downloads (tier=shell tools)
```

**Shell startup** (`~/.bashrc` or `~/.zshrc`) sources: `init.sh` → `env.sh` →
`tool-init.sh` (interactive only) → `generated/theme.sh` → `fzf.sh` →
`tools/*.sh` → `platform/wsl.sh` (when WSL) → `lazy/nvm.sh` → `~/.shell.local`.

**Project search roots** (`proj`, `fzf-project`, `cproj`) are unified behind
`PROJECTS_DIRS` (colon-separated, default `~/projects:~/work:~/dev:~/code:~/src`).
Override per-machine in `~/.shell.local`.

## Extending

**New tool:**
1. Add an entry to `lib/registry.sh` (`TOOL_BINARY`, `TOOL_METHOD`, `TOOL_TIER`, `TOOL_PATHS`).
2. For `eget`-installable binaries, add to `eget.toml`. Otherwise create `installers/install-<tool>.sh` and call it from the appropriate `install_<tier>` function in `lib/install.sh` via `run_installer "<tool>"`.
3. Add aliases/functions in `shell/tools/<domain>.sh`.
4. Add a row to `shell/shortcuts-index.tsv` for `cheatsheet`.

**New APT package:** Append to `PACKAGES[<group>]` in `lib/config.sh`.

**New config:** Add file to `configs/`, add a `[<file>]` block to `CONFIG_MAP` in `lib/config.sh` with `target=` (and optional `template=true`). Templates support `{{GIT_NAME}}`, `{{GIT_EMAIL}}`, `{{DOTFILES_DIR}}` substitution.

**New theme:** Create `themes/<name>/` with the required files (`meta.sh`, `colors.sh`, `vim.vim`, `tmux.conf`, `shell.sh`) — themes are auto-discovered from disk. Add per-tool palette files (`starship.palette.toml`, `delta.gitconfig`, `btop.theme`, `lazygit.yml`, optional `bat/<name>.tmTheme`) for full surface coverage.

**Local overrides:** `~/.shell.local` (sourced last by both shells) and `~/.bashrc.local` / `~/.zshrc.local` are sourced after dotfiles config and not tracked. Use them for machine-specific `PROJECTS_DIRS`, secrets, and personal aliases.

## Troubleshooting

```bash
./bin/verify                      # Validate installation
./setup.sh --dry-run --shell      # Preview what would happen
reload                            # Reload shell config
ls .backups/                      # See available backups
```
