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
| `--dev` | zsh, build tools, clipboard, Neovim and its pinned plugins, tmux, shellcheck, harper-ls | Yes |
| `--work` | NVM and pinned Node, Docker, rustup and the pinned Rust toolchain, and Docker Sandboxes (`sbx`) with KVM access where supported | Yes |

Each tier includes the ones before it. If you pass several tiers, the highest
one wins. Every tier runs on each supported platform; `sbx` and its KVM access
need native Ubuntu 24.04/26.04, so `--work` skips them on 22.04 and WSL2.

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

- `--dry-run` shows what would change, from what is installed now, and
  changes nothing; on an up-to-date machine it prints no actions.
- `--only X,Y` installs just those selected components; a need that is not
  installed blocks one instead of being installed, and configs are left alone.
- `--reinstall[=X,Y]` reinstalls components that dotfiles installed (all of
  the selection, or the named ones); `--overwrite-configs` replaces configs that
  differ, keeping backups; `--force` is both. Setup never replaces tools that
  something else installed unless you reinstall them.
- `--no-hooks` skips the repository's pre-commit hook.
- `--no-git` skips `~/.gitconfig`.
- `--git-name` and `--git-email` set your Git identity without a prompt.
- `--no-theme` and `--no-agent-badge` turn those features off, and they stay
  off until you re-enable them with `--theme`, `--agent-badge`, or
  `bin/dotfiles-feature`.

`./setup.sh --help` lists every option.

Each setup run adds its tier and selections to the machine profile
(`~/.local/state/dotfiles/profile`), which records what dotfiles manages on
this machine. Flags only add; a preview never writes it. `dotfiles profile`
shows it and changes it:

```bash
dotfiles profile                  # tier, capabilities, AI CLIs, opt-outs
dotfiles profile --add rdp        # save, show the plan, apply on confirmation
dotfiles profile --remove pi      # stop managing pi; it stays installed
dotfiles profile --tier dev       # lowering uninstalls nothing
dotfiles profile --propose        # derive one from what is installed
```

Every run, including `--dry-run`, writes a log to
`~/.local/state/dotfiles/logs/` (`latest.log` is the newest; the last 30 are
kept). It records the command, the checkout revision, the full output, and the
component ledger changes the run made. Set `DOTFILES_SETUP_LOG=0` to skip it.

After setup:

1. Restart the shell and run `dotfiles verify`.
2. Run `gh auth login` on each machine that needs GitHub access.

For `--work` host setup (KVM, `sbx login`, Tailscale enrollment, the pinned
sbx and its kit builder), see [docs/work.md](docs/work.md). Generic sbx kits
(Claude and Codex harnesses, an LLM gateway, your portable AI preferences) are
in [kits/](kits/README.md).

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
  `Alt+Paste` pastes the tmux buffer. Every copy, including nvim yanks and
  shell cuts, also goes to the client clipboard over OSC 52 (up to 64 KiB).
  Pause or `<prefix> E` turns that off (`CLIP OFF` shows in the status bar);
  `<prefix> e` still sends the buffer. `<prefix> v` enters copy mode on
  the screen as it is, and ScrollLock or `<prefix> f` reviews a
  pane: copy mode for shells and Claude's transcript, transcript search in
  Codex, the exported session in an nvim popup for OpenCode. In review,
  E/S/D/F move, Shift selects, `/` searches upward, and `o` opens the history
  in nvim. `<prefix> y` or Shift+Copy copies the agent's last reply.
  The wheel and PgUp/PgDn page less (`glow -p`, `md`, bat, Git) and Claude's
  transcript; in Claude, Shift+Up/Down scroll it a line at a time.
  In Claude, `Ctrl+C` sends Esc, so it can't stop every background agent;
  `<prefix> Ctrl+C` sends the real key. Ctrl+Backspace/Delete delete a word
  and Alt+Backspace/Delete to the line's start or end there too, as in the
  shell, Codex and nvim.
- **Compose:** `Alt+V` opens Neovim in a pane under an agent (Claude, Codex,
  OpenCode) for writing a prompt, with spell checking and, once `--dev` has
  installed harper-ls, grammar marks. `Ctrl+S` pastes the prompt and submits
  it without interrupting a running turn; `Ctrl+Shift+S` (or `,s`) pastes
  without submitting;
  PgUp/PgDn and Ctrl+Home/End scroll the agent. `Ctrl+L` in insert mode fixes
  the last spelling or grammar mark before the cursor. `Alt+V` again switches
  focus; the draft survives closing the pane.
  In development ([issues/compose-claude-box.md](issues/compose-claude-box.md)):
  in Claude, `Alt+V` and Claude's own `Ctrl+G` move what is in the prompt box
  into the compose pane, and quitting it (`:q`, `:wq`) puts the draft back in
  the box; `:cq` keeps it in the draft instead. `Ctrl+Shift+G` opens the
  prompt in Neovim in Claude's place, as `Ctrl+G` used to. This works for
  Claude sessions started from a shell with these dotfiles, where `VISUAL` is
  `bin/compose-editor`.
- **Windows Terminal:** merge
  [`configs/windows-terminal-keybindings.jsonc`](configs/windows-terminal-keybindings.jsonc)
  into `settings.json`.
- **WezTerm:** copy [`configs/wezterm.lua`](configs/wezterm.lua) to
  `%USERPROFILE%\.wezterm.lua`.
- **WSL:** adds `pbcopy`/`pbpaste`, `cdwin`, and `open`. To use a Windows SSH
  agent such as Bitwarden or 1Password, run `./bin/ssh-bridge enable`.

### AI CLIs

`bin/ai-config` merges the portable settings from `configs/` (`codex.toml`,
`claude-settings.json`, `opencode.json`, `opencode-cli.json`, and `ai/`) into
each CLI's own configuration. Enforced keys are the same everywhere; the
`.defaults` files are starting values each machine keeps once it changes them.
Settings not listed are left alone. See
[docs/ai-configuration.md](docs/ai-configuration.md).

```bash
./bin/ai-config --dry-run
./bin/ai-config --check --plugins
./bin/ai-update claude            # explicit update through the official installer
./bin/ai-update opencode          # opencode only notifies about new releases
```

`Alt+I` at a Bash or Zsh prompt, inside tmux or not, turns the request typed
there into a command: `find every JSON file changed in the last week` becomes
`find . -type f -name '*.json' -mtime -7`, to read, edit, and run with Enter;
nothing runs before that. `Alt+I` again asks for a correction (`refine> use
absolute paths and exclude node_modules`) in the same conversation, and
`Alt+Shift+I` starts a new one. It uses your Claude login with tools and
customizations off. See
[AI command drafting](docs/customization.md#ai-command-drafting-alti).

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

One global theme colors tmux and everything running in it: Neovim, fzf, bat,
Starship, delta, btop, and lazygit. Any tmux window can have its own theme. See
[docs/theme-system.md](docs/theme-system.md).

```bash
theme                                   # interactive picker (global)
theme -w vesper                         # theme only the current tmux window
theme -w clear                          # window follows the global theme again
theme --nvim gruvbox                    # Neovim keeps gruvbox (:Theme NAME for one editor)
```

Available themes: Gruvbox Material (four variants), Tokyo Night, Kanagawa
Wave/Dragon, Catppuccin Mocha/Latte, Everforest, Vesper, and GitHub Light.

## Local customization

Machine-specific settings go in these files. None of them are tracked.

- `~/.shell.env`: environment for every shell, agents' included, such as
  `PROJECTS_DIRS` or `EDITOR`.
- `~/.shell.local` and `~/.shell.local.d/*.sh`: aliases, functions, prompt,
  and secrets, for interactive shells only.
- `~/.gitconfig.local`: Git identity and commit signing.
- `~/.tmux.local.conf`: tmux options for this machine.
- `~/.ssh/config.local` and `~/.ssh/config.d/*.conf`: SSH host overrides.

See [docs/customization.md](docs/customization.md) for these files and for
adding tools, configs, and aliases.

## Maintenance

`dotfiles verify` checks the checkout, state, the profile's components,
configs, AI settings, and host readiness, and changes nothing. It prints only
what needs attention (`-v` lists every check) and exits 1 when setup has work
to do, 3 when a check could not be made, 2 when something needs you (Tailscale
enrollment, a group login), and 0 otherwise. `--latest` adds newer upstream
releases of pinned tools.

`dotfiles apply` brings the machine to the checkout and its profile without
pulling: it installs, moves, or repairs what the profile selects, runs their
configure steps, and deploys configs. `dotfiles update` takes upstream
changes: it fetches and shows them, fast-forwards the install-path checkout,
applies the profile, and verifies. It stops on uncommitted changes, a detached
HEAD, or a branch that has diverged from its upstream.

`dotfiles refresh` brings running processes up to date with the disk: the
tmux server's environment, config, badge, and theme. It lists shells and
programs that started before a change dotfiles made and need a restart
(`reload` a shell). Every apply, and so every update, ends with one refresh.

```bash
dotfiles update                   # pull, apply the profile, refresh, verify
dotfiles refresh                  # tmux up to date; list what needs a restart
dotfiles apply --dry-run          # what applying the profile would change
dotfiles apply --only node        # one component (blocked if nvm is missing)
dotfiles verify                   # this machine against the checkout and profile
./bin/verify --tier work          # a tier against current reality (also --all)
./bin/diff-config                 # drift between tracked configs and $HOME
./bin/check-updates               # every pin vs its newest release, plus advisories
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
| [theme-system](docs/theme-system.md) | Global and window themes, how programs follow them, adding themes |
| [work](docs/work.md) | Work-tier sandbox host, Tailscale, cloud CLIs |
| [ai-configuration](docs/ai-configuration.md), [ai-tools-egress](docs/ai-tools-egress.md), [opencode-secure](docs/opencode-secure.md) | AI CLI configuration and network egress |

This repository does not declare a license. Theme attributions are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
