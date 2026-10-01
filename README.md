# Dotfiles

Tiered dotfiles for Ubuntu 22.04/24.04/26.04 and WSL2 (x86_64 and aarch64).
The base tiers need no sudo, so the full shell environment also works on
managed machines where you can't get root.

## Install

On a fresh machine, `bootstrap.sh` installs Git if needed, clones the repo to
`~/dev/dotfiles` (override with `DOTFILES_DIR`), and runs `setup.sh`. It uses
`--bash` unless you pass other flags after `--`:

```bash
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh | bash -s -- --full --tail
```

From a checkout, run `./setup.sh` with a tier. With no arguments it prints help
and changes nothing.

| Tier | Adds | Sudo |
|---|---|---|
| `--config` | Links configs for tools that are already installed | No |
| `--bash` | Pinned CLI tools in `~/.local/bin` through eget: starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, gdu, glow, lazygit, gh, uv, sd, direnv | No |
| `--dev` | zsh, build tools, clipboard, Neovim, tmux, shellcheck | Yes |
| `--work` | NVM, Docker, Docker Sandboxes (`sbx`) with KVM access, Rust | Yes |

Each tier includes the ones before it. If you pass several tiers, the highest
one wins. `--work` requires native Ubuntu 24.04/26.04 with KVM. The other tiers
also run on 22.04 and WSL2.

The following selections combine with any tier:

| Flag | Adds |
|---|---|
| `--ai`, or `--claude` `--codex` `--opencode` `--pi` | AI CLIs: all four, or only the ones you name |
| `--full` | Same as `--work --ai` |
| `--tail` | Tailscale package and service; does not enroll the machine |
| `--rdp` | xrdp server with an XFCE session |
| `--azure` `--gcloud` `--aws` | Cloud CLIs |

`--full` never adds RDP, Tailscale, or cloud CLIs; you always choose those
explicitly. RDP in particular opens a network listener. Leave AI off where your
organization manages those CLIs. The shell helpers work with whatever `claude`, `codex`,
`opencode`, or `pi` is on `PATH`.

Setup options:

- `--dry-run` previews all changes.
- `--force` reinstalls components that dotfiles installed. Setup never replaces
  tools that something else installed unless you pass `--force`.
- `--no-hooks` skips the repository's pre-commit hook.
- `--no-git` skips `~/.gitconfig`.
- `--git-name` and `--git-email` set your Git identity without a prompt.
- `--no-theme` and `--no-agent-badge` turn those features off, and they stay
  off until you re-enable them with `--theme`, `--agent-badge`, or
  `bin/dotfiles-feature`.

`./setup.sh --help` lists every option.

After setup:

1. Restart the shell and run `./bin/verify --installed`.
2. After `--dev`, run `./bin/install-editor-plugins` to install Neovim plugins.
3. Run `gh auth login` on each machine that needs GitHub access.

For `--work` host setup (KVM, `sbx login`, Tailscale enrollment), see
[docs/work.md](docs/work.md).

## What you get

| Classic | Replacement | Alias |
|---|---|---|
| `ls` | eza | `ll`, `la`, `l`, `tree` |
| `cat` | bat | `view` |
| `find` / `grep` | fd / ripgrep | |
| `cd` | zoxide | `z`, `zi` |
| `diff` | delta | used automatically by Git |
| `top` | btop | `top` |
| `sed` | sd | used by `fr` |
| pip + venv | uv | `uvs`, `uvr`, `uva` |

`cheat` searches every alias, function, and keybinding, and `cheat commands`
lists the `bin/` utilities. Some common ones:

```bash
reload / mkcd <dir> / extract <archive>
proj / cproj              # fzf project picker (cd / VS Code)
fgb / fgl / frg           # fzf branch switcher / commit browser / ripgrep
gs ga gc gd gp gpl        # git status/add/commit/diff/push/pull
lg                        # lazygit
tm <name> / ta <name> / tr   # tmux new / attach / resume most recent
yo <command>              # print output and copy it to the clipboard
```

`proj` and `cproj` search the directories in `PROJECTS_DIRS` (default
`~/projects:~/work:~/dev:~/code:~/src`).

### Terminal and tmux

- **tmux:** `Alt+Copy` enters copy mode and copies the selection, and
  `Alt+Paste` pastes the tmux buffer. `<prefix> e` sends the buffer to the
  client clipboard (up to 64 KiB). OSC 52 is off by default; turn it on with
  `tmux set -g @clipboard-osc52 on`.
- **Windows Terminal:** merge
  [`configs/windows-terminal-keybindings.jsonc`](configs/windows-terminal-keybindings.jsonc)
  into `settings.json`.
- **WezTerm:** copy [`configs/wezterm.lua`](configs/wezterm.lua) to
  `%USERPROFILE%\.wezterm.lua`.
- **WSL:** adds `pbcopy`/`pbpaste`, `cdwin`, and `open`. To use a Windows SSH
  agent such as Bitwarden or 1Password, run `./bin/ssh-bridge enable`.

### AI CLIs

`bin/ai-config` merges the portable settings from `configs/codex.toml`,
`configs/claude-settings.json`, `configs/opencode.json`, and `configs/ai/` into each CLI's own
configuration. Settings not listed in those files are left alone. See
[docs/ai-configuration.md](docs/ai-configuration.md).

```bash
./bin/ai-config --dry-run
./bin/ai-config --check --plugins
./bin/ai-update claude            # explicit update (auto-update is disabled)
./bin/ai-update opencode          # opencode only notifies about new releases
```

`bin/viz` shows an agent's charts and diagrams through the VS Code window
connected over Remote-SSH, since agents in tmux cannot draw on the client
screen. `viz open` sends HTML, SVG and PDF to the client browser through a
localhost server that reloads pages on change, and opens other files as VS Code
tabs. Claude's `viz` skill tells it where to write output and how to render it.

```bash
viz path report.html              # ~/viz/<today>/report.html
viz open ~/viz/2026-09-28/report.html
viz status                        # server and VS Code connection
```

### Themes

A single theme applies across Neovim, tmux, fzf, bat, Starship, delta, btop, and
lazygit. You can set it globally or per tmux session or window, and override it
for individual tools. See [docs/theme-system.md](docs/theme-system.md).

```bash
theme                                   # interactive picker (global)
theme --window                          # picker for the current tmux window
theme set --window vim gruvbox          # override one tool in this window
theme explain --window                  # show which setting won, and from where
```

Available themes: Gruvbox Material (four variants), Tokyo Night, Kanagawa
Wave/Dragon, Catppuccin Mocha/Latte, Everforest, Vesper, and GitHub Light.

## Local customization

Machine-specific settings go in these files. None of them are tracked.

- `~/.shell.local` and `~/.shell.local.d/*.sh`: aliases, exports, secrets, and
  `PROJECTS_DIRS`.
- `~/.gitconfig.local`: Git identity and commit signing.
- `~/.ssh/config.local` and `~/.ssh/config.d/*.conf`: SSH host overrides.

See [docs/customization.md](docs/customization.md) for these files and for
adding tools, configs, and aliases.

## Maintenance

```bash
./bin/verify --installed          # health of what this machine recorded
./bin/diff-config                 # drift between tracked configs and $HOME
./bin/check-updates               # pinned tool versions vs latest releases
./bin/uninstall-tool --dry-run X  # remove a component that dotfiles installed
ls ~/.local/state/dotfiles/backups/   # configs replaced during setup
```

## Documentation

| Document | Covers |
|---|---|
| [architecture](docs/architecture.md) | Shell layers, installation model, state, ownership |
| [customization](docs/customization.md) | Adding tools, configs, aliases; local overrides; SSH and Git per machine |
| [maintenance](docs/maintenance.md) | Development workflow, updates, ownership, recovery |
| [testing](docs/testing.md) | Test isolation, platform coverage, manual checklists |
| [supply-chain](docs/supply-chain.md) | Download trust and replacement guarantees per component |
| [theme-system](docs/theme-system.md) | Theme scopes, resolution order, runtime behavior, adding themes |
| [work](docs/work.md) | Work-tier sandbox host, Tailscale, cloud CLIs |
| [ai-configuration](docs/ai-configuration.md), [ai-tools-egress](docs/ai-tools-egress.md), [opencode-secure](docs/opencode-secure.md) | AI CLI configuration and network egress |

This repository does not declare a license. Theme attributions are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
