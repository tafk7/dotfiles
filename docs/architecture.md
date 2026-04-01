# Dotfiles Architecture

## Overview

This dotfiles system manages an Ubuntu/WSL development environment through a tiered
installation system (`--config`, `--shell`, `--dev`, `--full`) with declarative
configuration, domain-split shell modules, and unified theme management.

## System Architecture

```
setup.sh ─┬─ source → lib/install.sh (pulls in runtime.sh + config.sh)
           └─ calls  → installers/install-*.sh

entry/bash.sh ─┐
entry/zsh.sh  ─┤─ source → entry/profile.sh → shell/env.sh
               └─ source → shell/init.sh
                            ├─ shell/env.sh (idempotent, guarded)
                            ├─ shell/tool-init.sh (interactive only)
                            ├─ shell/tools/*.sh
                            ├─ shell/lazy/nvm.sh
                            └─ starship init / zoxide init

bin/*     ──── source → lib/runtime.sh
```

### Boundary Rules

- `lib/install.sh` — sourced only by `setup.sh` and `installers/`. Never at shell startup.
- `lib/runtime.sh` — safe for all contexts (bin/, shell startup).
- `lib/config.sh` — declarative data (CONFIG_MAP, PACKAGES). No functions, no side effects.
- `shell/env.sh` — static exports and PATH composition. No eval, no subshells.
- `shell/tool-init.sh` — all `eval` calls (pyenv, direnv, completions). Interactive only.
- `shell/tools/*.sh` — domain-split functions and aliases (one file per tool domain).

## Directory Layout

```
dotfiles/
├── setup.sh                  ← orchestrator (reads lib/config.sh)
├── lib/
│   ├── install.sh            ← install-time helpers
│   ├── runtime.sh            ← runtime helpers (logging, is_wsl, verify_binary)
│   ├── config.sh             ← declarative data: CONFIG_MAP + PACKAGES
│   └── registry.sh           ← TOOL_BINARY/METHOD/TIER/PATHS/VERIFY data
├── eget.toml                 ← binary tool manifest
├── configs/                  ← config files symlinked to $HOME
│   ├── gitconfig             → ~/.gitconfig (template)
│   ├── tmux.conf, init.vim, editorconfig, ripgreprc, starship.toml
│   ├── ssh_config, config/bat, config/fd
├── entry/
│   ├── bash_profile          → ~/.bash_profile (sources .bashrc)
│   ├── bash.sh               → ~/.bashrc
│   ├── profile.sh            → ~/.profile
│   └── zsh.sh                → ~/.zshrc
├── generated/
│   ├── bridge.sh             ← DOTFILES_DIR export (written by setup.sh)
│   └── theme.sh              ← active theme colors (written by theme-switcher)
├── installers/               ← per-tool install scripts
├── shell/
│   ├── init.sh               ← shared sourcing sequence for bash + zsh
│   ├── env.sh                ← PATH composition + static exports (single source of truth)
│   ├── tool-init.sh          ← eval-based init (pyenv, direnv, completions)
│   ├── fzf.sh                ← FZF configuration
│   ├── lazy/nvm.sh           ← lazy NVM loader for both shells
│   ├── tools/                ← domain-split functions and aliases
│   │   ├── claude.sh, docker.sh, fzf.sh, general.sh, git.sh
│   │   ├── nav.sh, node.sh, process.sh, python.sh
│   │   ├── tmux.sh, vim.sh, vscode.sh
│   └── platform/wsl.sh      ← WSL-specific functions
├── themes/                   ← color themes (5 themes)
│   └── <name>/ {colors.sh, meta.sh, shell.sh, tmux.conf, vim.vim}
├── bin/
│   ├── theme-switcher, verify, replace, cheatsheet
��   ├── uninstall-tool, git-credential-azdo
└── docs/
```

## Environment Management

### Single source of truth: `shell/env.sh`

All PATH composition and static exports live in one file: `shell/env.sh`.
No other file modifies PATH (except `shell/tool-init.sh` which re-prepends
pyenv shims via `eval` in interactive shells).

```
shell/env.sh owns:
  PATH additions     ~/bin, ~/.local/bin, /usr/local/bin
                     $NVM_DIR/default/bin
                     $PYENV_ROOT/bin
                     $GOPATH/bin, $CARGO_HOME/bin

  Static exports     NVM_DIR, PYENV_ROOT, GOPATH, CARGO_HOME
                     EDITOR, VISUAL, PYTHONDONTWRITEBYTECODE
                     NODE_OPTIONS, DOCKER_BUILDKIT, BAT_THEME

  WSL environment    DISPLAY, BROWSER, WSLENV, WIN_HOME
                     PATH stripping (Windows system dirs)
```

`env.sh` has an idempotency guard (`_DOTFILES_ENV_LOADED`) so it's safe
to source multiple times — `.profile` sources it, then `init.sh` sources
it again. Only the first invocation modifies state.

### Initialization chains

Every shell context reaches `env.sh` through one of these paths:

```
Login bash:          .bash_profile → .bashrc → .profile → env.sh
                                                        → init.sh → env.sh (guarded)

Non-interactive bash: .bashrc → .profile → env.sh → return
(scripts, Claude Code)

Interactive bash:    .bashrc → .profile → env.sh
(VS Code terminal)           → init.sh → env.sh (guarded) → tool-init.sh → tools/*

Login zsh:           .zshrc → .profile → env.sh → init.sh → env.sh (guarded)
```

### NVM two-tier strategy

- **Non-interactive**: `env.sh` adds `$NVM_DIR/default/bin` to PATH — a
  stable symlink created by `install-nvm.sh` pointing to the active LTS.
  No `nvm.sh` sourcing needed. `node`, `npm`, `npx` are immediately available.
- **Interactive**: `shell/lazy/nvm.sh` installs stub functions that source
  `$NVM_DIR/nvm.sh` on first call (~200ms deferred until needed).

### Claude Code compatibility

Claude Code runs each Bash tool invocation as a fresh subprocess with a
shell snapshot captured at session start. The snapshot freezes PATH and
environment variables from the moment Claude Code launched.

This means PATH must be correct at snapshot time — which is why all PATH
composition lives in `env.sh` rather than being split across files. The
chain `.bashrc` → `.profile` → `env.sh` runs in every context, including
Claude Code's non-interactive snapshot capture. If `env.sh` is correct,
the snapshot is correct.

When adding a new tool to PATH:
1. Add the `[[ -d ... ]] && PATH=...` line to `shell/env.sh`
2. Restart Claude Code to re-capture the snapshot
3. Do NOT add PATH entries in `.profile`, `init.sh`, or tool-specific files

## Installation Tiers

| Tier   | What It Installs                                   | Sudo? |
|--------|---------------------------------------------------|-------|
| config | Symlinks only (zero installs)                      | No    |
| shell  | + eget tools, APT packages (bat, fd, rg, direnv)  | Yes   |
| dev    | + neovim, tmux                                     | Yes   |
| full   | + NVM, pyenv, poetry, Docker, Azure CLI            | Yes   |

## Key Design Decisions

1. **Single PATH authority** (`shell/env.sh`) — all PATH additions in one
   file. Works for login shells, non-interactive subshells, VS Code
   terminals, and Claude Code's shell snapshot mechanism.

2. **Lazy NVM** (`shell/lazy/nvm.sh`) — both shells defer `nvm.sh` loading
   until first `nvm`, `node`, `npm`, or `npx` call. Eliminates ~200ms
   startup penalty. Non-interactive contexts use the `default/bin` symlink.

3. **Single CONFIG_MAP** (`lib/config.sh`) — both the installer and
   verifier read the same data. Adding a config automatically extends
   verification.

4. **Domain-split tools** — each file in `shell/tools/` owns one domain.
   Finding where a function lives is self-evident from the filename.

5. **Idempotent sourcing** — `env.sh` and `.profile` have guards so they're
   safe to source multiple times from different init paths.
