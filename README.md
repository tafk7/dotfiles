# Dotfiles — Ubuntu Development Environment

Tiered dotfiles system for Ubuntu/WSL. Install only what you need: from config-only (no sudo) to complete development environment.

## Quick Start

```bash
./setup.sh                       # No args: prints help, changes nothing
./setup.sh --config              # Reconcile symlinks to installed tools (no sudo)
./setup.sh --bash                # + starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, gh, direnv (NO sudo — eget)
./setup.sh --dev                 # + zsh, build tools, neovim, tmux (first sudo tier)
./setup.sh --work                # + NVM, Docker, local sbx/KVM readiness, Rust
./setup.sh --ai                  # + all AI CLIs: Claude Code, Codex, opencode, Pi (orthogonal)
./setup.sh --claude --opencode   # + only the AI CLIs you name (--claude / --codex / --opencode / --pi)
./setup.sh --rdp                 # + xrdp RDP server + XFCE desktop (orthogonal flag; combines with any tier)
./setup.sh --tail                # + Tailscale package/service (orthogonal; no enrollment)
./setup.sh --azure               # + Azure CLI and Azure DevOps Git integration
./setup.sh --gcloud              # + Google Cloud CLI
./setup.sh --aws                 # + AWS CLI v2
./setup.sh --full                # Exactly --work plus --ai
./setup.sh --dev --ai            # Dev environment + self-managed AI CLIs
./setup.sh --bash --no-theme      # Core shell with the default theme feature disabled
./setup.sh --ai --no-agent-badge # AI CLIs without the optional tmux badge plugin
./setup.sh --bash --dry-run      # Preview without changes
./setup.sh --bash --no-hooks     # Skip the pre-commit lint hook (default: installed)
```

The tiers `config → bash → dev → work` are cumulative (each includes the
previous). `--ai` is **orthogonal**: it installs the AI CLIs (Claude Code,
Codex, opencode, Pi) and can be added to any tier. Install them individually with
`--claude`, `--codex`, `--opencode`, and/or `--pi` (they compose: `--claude --opencode`
installs just those two). Leave AI off entirely when your org manages the
install — the shell aliases/shortcuts load regardless and resolve whatever
`claude`/`codex`/`opencode`/`pi` is on your `PATH`. `--full` is shorthand for
`--work --ai`. It never implies Tailscale, RDP, or cloud CLIs. Multiple tier flags select the highest tier regardless of order.
Use `--force` to refresh dotfiles-owned components; externally managed tools are
never replaced implicitly.

The **sudo boundary sits at `dev`**: `config` and `bash` need no root — every
bash-tier tool installs to `~/.local/bin` via eget — so the full modern shell
experience works on a managed machine where you can't `sudo`. `dev` and up add
the APT layer (zsh, build tools, clipboard) and require sudo. On the bash tier a
tool already installed system-wide is left in place (use `--force` to install our
pinned copy over it).

Because local sandbox execution is part of `work`, that tier requires native
Ubuntu 24.04/26.04 with KVM. The config, bash, and dev tiers retain Ubuntu
22.04 and WSL support.

`--rdp` is a second orthogonal flag: it installs and configures the xrdp RDP
server with an XFCE session so you can remote into this machine's desktop
(WSL: `mstsc -> localhost:3390` from the Windows host). It is deliberately
**not** part of `--full` — opening a network listener is always an explicit
opt-in. Details: `issues/xrdp-remote-desktop.md`.

`--tail`, `--azure`, `--gcloud`, and `--aws` are orthogonal. The work tier
installs Docker Engine, local Docker Sandboxes (`sbx`), and KVM host access on
native Ubuntu 24.04/26.04. `--tail` adds Tailscale without enrollment. Tailscale
and APT-backed cloud selections require sudo independently of the tier. See
[docs/work.md](docs/work.md).

Compatibility change: fresh `--work` and `--full` runs no longer install Azure
CLI. Use `--work --azure` to retain that selection. Existing Azure installs are
left in place, and no cloud CLI is inferred from the VM's provider.

The coordinated theme is enabled by default and agent-badge is enabled when a
supported AI CLI is selected. Both are optional, persistent preferences:
`--no-theme` and `--no-agent-badge` remain in effect until `--theme` or
`--agent-badge` is explicitly requested (or `bin/dotfiles-feature` is used).

After installation, verify with `./bin/verify --installed` and restart your shell.
GitHub CLI authentication remains machine-local; run `gh auth login` on each
machine where authenticated GitHub access is wanted.

This repository does not currently declare an overall software license. Theme
attribution is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Fresh machine (one-liner)

No clone step needed — `bootstrap.sh` installs git, clones this repo, and runs
`setup.sh`:

```bash
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash -s -- --dev
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh \
  | bash -s -- --full --tail
```

The repo lands in `~/dev/dotfiles` (override with `DOTFILES_DIR`). Defaults to the
`--bash` tier; pass any tier flag after `--`.

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
| `sed` | sd | (used by `fr`) |
| `less` for md | glow | `md` |
| `git` TUI | lazygit | `lg` |
| pip+venv | uv | `uvs`, `uvr`, `uva` |

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
# uv owns Python: interpreters, venvs, dependencies, and tools
uv python install 3.11   # Install an interpreter
uv venv --python 3.11    # Create .venv on a specific version
uv python pin 3.11       # Write .python-version for the project
vactivate                # Activate .venv (or just use `uv run`)

# uv shortcuts
uvs / uvr / uva / uvpi    # sync / run / add / pip install

# direnv auto-activation (recommended)
uv venv && echo 'source .venv/bin/activate' > .envrc && direnv allow
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
nclean                    # preserve lockfile; npm ci when one exists
nuke-node                 # explicitly remove node_modules and lockfiles
```

### Tmux

```bash
tm <name> / ta <name>     # New session / attach named session
tr                       # Resume most recently used session
tl / tk <name>            # List / kill session
```

Clipboard: `Alt+Copy` (physical Copy is `Ctrl+Insert`) enters copy mode and
confirms an active selection; `y` is the fallback. `Alt+Paste` pastes the tmux
buffer, while plain Copy/Paste remain Windows Terminal actions. OSC 52 export
is disabled by default; toggle it with `tmux set -g @clipboard-osc52 on|off`.
Alt-click enters tmux copy mode; Alt-drag, Alt-double-click, and Alt-triple-click
copy a selection, word, or line directly to the tmux buffer. Shift-drag selects
in the client.
`<prefix> e` explicitly exports the current tmux buffer to the Windows/client
clipboard through the same 64 KiB size gate.
`<prefix> i` inserts the current window at a prompted index (`-1` means the
end).

### WSL (auto-detected)

```bash
pbcopy / pbpaste          # Clipboard integration
cdwin / cddesk / cddl     # Navigate to Windows directories
open / explorer           # Open in Windows Explorer
```

Windows Terminal: merge the `actions` and `keybindings` arrays from
[`configs/windows-terminal-keybindings.jsonc`](configs/windows-terminal-keybindings.jsonc)
into the client machine's `settings.json`. The fragment preserves native
Copy/Paste, forwards Alt+Copy/Paste to tmux, adds TAFK tab controls, and removes
the competing Windows Terminal pane keymap. Shift-modified Backspace/Delete
cuts word- or line-sized command-line ranges into the shared tmux buffer.

WezTerm alternative: copy [`configs/wezterm.lua`](configs/wezterm.lua) to
`%USERPROFILE%\.wezterm.lua`. It provides the same TAFK/tmux key surface with
the normal WezTerm palette, no native pane shortcuts, and reduced client-side
scrollback. Remote shells and applications remain responsible for their own
ANSI/truecolor styling.

Codex: [`configs/codex.toml`](configs/codex.toml) is the portable base. The
Codex installer refreshes only its marked block in `~/.codex/config.toml`, so
project trust, hook trust, plugins, and private provider selections remain
machine-local. If bindings are changed through Codex's `/keymap` UI, mirror the
resulting `tui.keymap` entries back into the tracked config.

## Theme System

Scoped themes applied across **eight surfaces** with a single command:
neovim, tmux, FZF, bat, Starship, Delta, btop, and lazygit.

```bash
./bin/theme-switcher              # Interactive FZF selection
./bin/theme-switcher --session    # Pick current session default
./bin/theme-switcher --window     # Pick current window default
./bin/theme-switcher --window vim # Pick current window's Vim override
./bin/theme-switcher -s           # Short session form
./bin/theme-switcher -w tmux      # Short window/tool form
./bin/theme-switcher kanagawa     # Direct switch
./bin/theme-switcher --preview tokyo-night
./bin/theme-switcher --revert     # Revert to previous
./bin/theme-switcher --list       # Show available themes
./bin/theme-switcher --init       # Re-render all surfaces from current theme
./bin/theme-switcher diagnose     # Real default/ANSI/truecolor samples
./bin/theme-switcher disable      # Persistent neutral fallback; unwire live tmux
./bin/theme-switcher enable       # Re-enable, render cache, and sync live tmux
./bin/dotfiles-feature status     # Inspect theme and agent-badge preferences
./bin/dotfiles-feature disable agent-badge  # Unwire badge without deleting data
```

**Global, session, window, and per-component overrides:**

```bash
./bin/theme-switcher set code tokyo-night       # editor group → tokyo-night
./bin/theme-switcher set starship kanagawa      # just starship → kanagawa
./bin/theme-switcher set --session default catppuccin
./bin/theme-switcher set --window vim gruvbox
./bin/theme-switcher explain --window           # effective value + source
./bin/theme-switcher unset starship             # back to chrome group/global
./bin/theme-switcher reset --window             # clear this window scope
```

Resolution is window tool/group/default, then session tool/group/default, then
global tool/group/default. Groups: `code` (vim, bat, delta), `chrome` (tmux,
starship, fzf), and `apps` (btop, lazygit). See
[docs/theme-system.md](docs/theme-system.md).

**Available:** Kanagawa Wave/Dragon, Tokyo Night, Gruvbox Material
(medium, classic, light, and light-soft), Catppuccin Mocha/Latte, Everforest,
Vesper, and GitHub Light.

Per-tool palettes live under `themes/<name>/`:

| File                          | Consumer                                  |
|-------------------------------|-------------------------------------------|
| `meta.sh`                     | Theme metadata (display name, description)|
| `colors.sh`                   | Canonical hex/RGB palette                 |
| `palette.sh`                  | Semantic roles + scoped ANSI palette      |
| `vim.vim`                     | Neovim/vim colorscheme + overrides        |
| `tmux.conf`                   | tmux status bar + pane borders            |
| `shell.sh`                    | Native `BAT_THEME`/`STARSHIP_PALETTE`/Delta feature names |
| `starship.palette.toml`       | Starship `[palettes.<name>]` block        |
| `delta.gitconfig`             | Delta `[delta "<name>"]` feature          |
| `btop.theme`                  | btop color theme                          |
| `lazygit.yml`                 | lazygit `gui.theme` block                 |
| `bat/<name>.tmTheme` (opt.)   | bat tmTheme — only when not a bat builtin |

Durable preferences live in `${XDG_STATE_HOME:-~/.local/state}/dotfiles/`.
Rebuildable theme artifacts live in `${XDG_CACHE_HOME:-~/.cache}/dotfiles/theme/`.
The bat cache
is **isolated** (`BAT_CACHE_PATH`) so it doesn't pollute delta's embedded
bat (different versions are binary-incompatible).

## Architecture

> **New here?** Read [`docs/concepts.md`](docs/concepts.md) first — it explains
> the four pillars (tiers, CONFIG_MAP, tool registry, theme cascade) on one page.

```
setup.sh                  Entry point — 3-phase orchestrator (reads lib/config.sh)
lib/
  install.sh              Install-time helpers (APT, backup, eget, tier functions)
  state.sh                Versioned preferences, component ledger, locks, journal
  runtime.sh              Runtime helpers (logging, is_wsl, command_exists)
  config.sh               Declarative data: CONFIG_MAP + PACKAGES
  registry.sh             Tool registry: binaries, tiers, capabilities, ownership, verify/update metadata
configs/                  Config files without dots (symlinked to ~/.<name>)
themes/                   Theme data — see "Theme System" table above
shell/
  init.sh                 Single sourcing sequence for bash + zsh
  env.sh / env-runtime.sh Layer 0: environment and project activation
  interactive/theme-env.sh Optional theme adapter
  fzf.sh / tool-init.sh   Tool initializers (zoxide, starship, fzf keybinds)
  tools/*.sh              Domain-split functions + aliases (nav, process, python, fzf, vscode, claude, docker, git, node, tmux, vim, general)
  platform/wsl.sh         WSL-only helpers (pbcopy/pbpaste, cdwin)
  lazy/nvm.sh             Lazy NVM loader
installers/               Per-tool install scripts (run by lib/install.sh::run_installer)
bin/                      User commands (theme-switcher, dotfiles-feature, verify, cheatsheet, replace, diff-config, check-updates, uninstall-tool, install-git-hooks)
eget.toml                 Static binary downloads (tier=bash tools)
```

**Shell startup** loads Layer 0 (`profile.sh` → `env-runtime.sh` → `env.sh`) in
startup-reading non-interactive shells. Interactive shells continue through
`init.sh` → optional theme adapter → `tool-init.sh` → `fzf.sh` →
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

**New config:** Add the file to `configs/`, then add a `target:type:owner` entry
to `CONFIG_MAP` in `lib/config.sh`. Git uses an include-based portable config;
machine identity belongs in `~/.gitconfig.local`.

**New theme:** Create `themes/<name>/` with the required files (`meta.sh`, `colors.sh`, `vim.vim`, `tmux.conf`, `shell.sh`) — themes are auto-discovered from disk. Add per-tool palette files (`starship.palette.toml`, `delta.gitconfig`, `btop.theme`, `lazygit.yml`, optional `bat/<name>.tmTheme`) for full surface coverage.

**Local overrides:** `~/.shell.local` is sourced last by both shells, after all dotfiles config. Not tracked. Use it for machine-specific `PROJECTS_DIRS`, secrets, and personal aliases. For shell-specific tweaks (`setopt`, `bindkey`, `shopt`), gate the block:

```bash
# ~/.shell.local
export PROJECTS_DIRS="$HOME/work/acme:$HOME/projects"
alias work='cd ~/work/acme'

if [[ -n "$ZSH_VERSION" ]]; then
    setopt HIST_FIND_NO_DUPS
elif [[ -n "$BASH_VERSION" ]]; then
    shopt -s autocd
fi
```

## Troubleshooting

```bash
./bin/verify --installed          # Validate recorded installation health
./bin/verify --tier bash          # Validate a requested profile
./bin/verify --all                # Inspect every applicable component
./bin/dotfiles-feature status     # Inspect persistent feature preferences
./bin/diff-config                 # Show drift between sources and ~ (use --diff for details)
./bin/check-updates               # Are pinned eget tool versions stale?
./bin/cheatsheet commands         # List all bin/ utilities (auto-generated from headers)
./setup.sh --dry-run --bash       # Preview what would happen
./bin/install-git-hooks --check   # Are dotfiles git hooks installed in this clone?
reload                            # Reload shell config
ls ~/.local/state/dotfiles/backups/  # See recoverable displaced configs
```

`bin/check-updates` uses the GitHub releases API. It auto-detects auth from
`GITHUB_TOKEN` or, if `gh` is installed and authenticated, from `gh auth token`;
otherwise it runs unauthenticated (60 req/hr). The summary line shows which
auth method was used.

## Further reading

- [`docs/concepts.md`](docs/concepts.md) — One-page mental model of the four pillars.
- [`docs/architecture.md`](docs/architecture.md) — Boundary rules and sourcing order.
- [`docs/customization.md`](docs/customization.md) — Recipes for adding tools, configs, aliases.
- [`docs/theme-system.md`](docs/theme-system.md) — Cascade internals + adding themes.
- [`docs/supply-chain.md`](docs/supply-chain.md) — Download trust and update-failure contracts.
- [`docs/testing.md`](docs/testing.md) — Hermetic matrix and manual WSL/RDP checks.
- [`docs/work.md`](docs/work.md) — Local sandbox setup, optional Tailscale, authentication, and lifecycle.
- [`docs/THEME_QUICK_START.md`](docs/THEME_QUICK_START.md) — Day-to-day theme commands.
