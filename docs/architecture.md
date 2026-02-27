# Dotfiles Architecture

## Overview

This dotfiles system manages an Ubuntu/WSL development environment through a tiered
installation system (`--config`, `--shell`, `--dev`, `--full`) with declarative
configuration, domain-split shell modules, and unified theme management.

## System Architecture

```
setup.sh ─┬─ source → lib/install.sh (pulls in runtime.sh + config.sh)
           └─ calls  → installers/install-*.sh

shell/bash.sh ─┐
shell/zsh.sh  ─┤─ source → shell/shared.sh
               │            ├─ env.sh → theme → fzf.sh
               │            ├─ functions/*.sh
               │            └─ aliases/*.sh
               ├─ source → shell/nvm-lazy.sh
               └─ shell-specific (prompt, completion, keybindings)

bin/*     ──── source → lib/runtime.sh
```

### Boundary Rules

- `lib/install.sh` — sourced only by `setup.sh` and `installers/`. Never at shell startup.
- `lib/runtime.sh` — safe for all contexts (bin/, shell startup).
- `lib/config.sh` — declarative data (CONFIG_MAP, PACKAGES). No functions, no side effects.
- `shell/functions/` — only function definitions.
- `shell/aliases/` — only alias declarations.

## Directory Layout

```
dotfiles/
├── setup.sh                  ← orchestrator (reads lib/config.sh)
├── lib/
│   ├── install.sh            ← install-time helpers
│   ├── runtime.sh            ← runtime helpers (logging, is_wsl, verify_binary)
│   └── config.sh             ← declarative data: CONFIG_MAP + PACKAGES
├── eget.toml                 ← binary tool manifest
├── configs/                  ← config files symlinked to $HOME
│   ├── gitconfig             → ~/.gitconfig (template)
│   ├── tmux.conf, init.vim, editorconfig, ripgreprc, starship.toml
│   ├── ssh_config, config/bat, config/fd
│   └── init.vim.minimal, tmux.conf.minimal
├── installers/               ← per-tool install scripts
├── shell/
│   ├── shared.sh             ← single sourcing sequence for bash + zsh
│   ├── bash.sh               → ~/.bashrc
│   ├── zsh.sh                → ~/.zshrc
│   ├── profile.sh            → ~/.profile
│   ├── env.sh                ← tool init (pyenv, direnv, EDITOR, WSL env)
│   ├── fzf.sh                ← FZF configuration
│   ├── nvm-lazy.sh           ← lazy NVM loader for both shells
│   ├── functions/            ← domain-split shell functions
│   │   ├── nav.sh            (cdl, mkcd, proj, PATH utils, md)
│   │   ├── process.sh        (psg, fkill, killport, extract)
│   │   ├── python.sh         (pyset, pyinfo, pylist, vactivate)
│   │   ├── fzf.sh            (fzf-git-branch/log/rg/project + aliases)
│   │   ├── wsl.sh            (import_windows_ssh_keys, winapp, winopen)
│   │   ├── tmux.sh           (pane-tint)
│   │   ├── docker.sh         (denter, dstopall)
│   │   └── git.sh            (gundo)
│   ├── aliases/              ← pure alias files
│   └── shortcuts-index.tsv
├── themes/                   ← color themes (5 themes)
│   └── <name>/ {colors.sh, shell.sh, tmux.conf, vim.vim}
├── bin/
│   ├── theme-switcher        (sources lib/runtime.sh, reads themes/)
│   ├── verify                (derives checklist from lib/config.sh + eget.toml)
│   ├── replace               (composes rg + sd)
│   ├── cheatsheet, uninstall-tool, vim-config-switcher, tmux-config-switcher
│   └── git-credential-azdo
└── docs/
```

## Installation Tiers

| Tier   | What It Installs                                   | Sudo? |
|--------|---------------------------------------------------|-------|
| config | Symlinks only (zero installs)                      | No    |
| shell  | + eget tools, APT packages (bat, fd, rg, direnv)  | Yes   |
| dev    | + neovim, tmux                                     | Yes   |
| full   | + NVM, pyenv, poetry, Docker, Azure CLI            | Yes   |

## Key Design Decisions

1. **Shared sourcing sequence** (`shell/shared.sh`) — both bash and zsh
   source it. Adding a new shared module requires editing one file.

2. **Lazy NVM** (`shell/nvm-lazy.sh`) — both shells defer nvm.sh loading
   until first `nvm`, `node`, `npm`, or `npx` call. Eliminates ~200ms
   startup penalty.

3. **Single CONFIG_MAP** (`lib/config.sh`) — both the installer and
   verifier read the same data. Adding a config automatically extends
   verification.

4. **Domain-split functions** — each file in `shell/functions/` owns one
   domain. Finding where a function lives is self-evident from the filename.
