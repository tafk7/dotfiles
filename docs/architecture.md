# Dotfiles architecture

This repository supports Ubuntu 22.04/24.04/26.04 on x86_64, Ubuntu
24.04/26.04 on aarch64, and WSL2 on Windows 11. Package tier, optional features,
platform, and architecture are separate decisions.

## Runtime layers

```text
Layer 0: entry/profile.sh -> shell/env-runtime.sh -> shell/env.sh
  locale, XDG paths, PATH, editor, project environment, direnv
  safe for startup-reading non-interactive Bash and Zsh

Layer 1: shell/init.sh
  shell options, history, completion, aliases/functions, prompt fallback

Layer 2: optional/default features
  WSL adapter and independently installed agent-badge plugins
```

Login Bash follows `.bash_profile -> .bashrc -> .profile`. Non-login
interactive Bash follows `.bashrc -> .profile`. A startup-reading
non-interactive Bash stops after Layer 0; plain `bash -c` and Bash shebangs do
not read these files.

Zsh always reads `.zshenv`, which loads Layer 0, and reads `.zshrc` only for
interactive sessions. Layer 0 does not resolve themes, query tmux, define public
interactive commands, or remove externally owned functions.

Startup locates the checkout (`DOTFILES_DIR`) in this order; a checkout is
valid when `$DOTFILES_DIR/shell/env.sh` exists:

1. the `.bashrc` or `.zshenv` symlink, when it resolves to a valid checkout;
2. an inherited, valid `DOTFILES_DIR`;
3. the recorded `install-path`;
4. `~/dev/dotfiles`.

Step 1 lives in `entry/bash.sh` and `entry/zshenv`; steps 2–4 live once, in
`entry/profile.sh`. An inherited value never overrides a resolvable symlink, so
a test HOME linked to a worktree, or a new tmux pane after a checkout switch,
uses the linked checkout.

Project activation follows shell startup semantics: `zsh -c` refreshes direnv
through `.zshenv`; plain `bash -c` reads no dotfiles and inherits its parent's
environment, while `bash -lc` refreshes through the login chain.

## Installation dimensions

The cumulative package tiers are `config -> bash -> dev -> work`; work includes
Docker, local sbx/KVM readiness, NVM, and Rust. AI tools, RDP, Tailscale, and
cloud CLIs are orthogonal selections. The theme feature is enabled by default but can
be persistently disabled. Agent-badge is enabled by default when a supported AI
CLI is installed and can be independently disabled.

```bash
./setup.sh --bash
./setup.sh --dev --ai
./setup.sh --bash --no-theme
./setup.sh --ai --no-agent-badge
./setup.sh --full --tail --gcloud
```

Multiple tier flags select the highest tier, independent of argument order.
`--full` always means `--work --ai`; it never enables Tailscale, RDP, or cloud
CLIs. Orthogonal selections retain the config baseline and never promote the
cumulative tier. Component-ledger outcomes retain partial Tailscale failures
without turning later config reconciliation into package installation.

## State and ownership

Durable state lives under
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/`:

- `preferences.tsv`: explicit feature preferences;
- `components.tsv`: observed component status, ownership, version, path, and
  update contract;
- `theme.tsv`: global theme selection;
- `install-path`: fallback checkout discovery for flattened deployments;
- `transaction.tsv`: an interrupted artifact replacement journal;
- `backups/`: displaced user configuration.

These files have a version header, contain data only, are validated before use,
and are atomically replaced. Read-modify-write operations use a bounded
inter-process lock with conservative stale-lock recovery. Setup reconciles an
incomplete artifact journal before starting another install; verification
reports a pending journal as a failure. The checkout is not the machine-state
database.

## Configuration ownership

`lib/config.sh` maps each source to `target:type:owner`. Base configuration is
always reconciled; tool-owned configuration is only installed when its owner is
present. Symlinks are unchanged on an idempotent rerun, and backups are created
lazily only when real user data is displaced.

Portable Git behavior is rendered to
`${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/gitconfig` and included by the
user's existing `~/.gitconfig`. Identity and machine-local overrides stay in
`~/.gitconfig.local`.

## Component registry

`lib/registry.sh` is the shared inventory for setup, verification, update
reporting, and uninstall. Each component is one row in its core table (binary,
installation method, tier, capabilities, platform, architectures, Ubuntu
releases, APT package, and presence check), plus optional override lines for
ownership roots, update contract, uninstall paths where automated removal is
safe, and removal notes. Defaults follow from the method, so a typical eget tool
needs no overrides. The tables are parsed once into `TOOL_*` arrays.
The tier records only cumulative membership. Composable, comma-separated
capabilities record AI, RDP, Tailscale, and cloud membership. Docker and sbx are
ordinary work-tier components.

Presence is checked by `tool_is_present` from a typed verify column (`command`,
`runs`, `service-active`, `file-nonempty`, or a named predicate), never by
evaluating stored shell text. Companion executables participate in
installation, verification, and uninstall. Successful installation establishes
ownership; observing or skipping a local binary does not. See the
[ownership and recovery contract](maintenance.md#updates-and-ownership).

Eget downloads are staged and executed before an atomic replacement. Neovim and
tmux also stage their artifacts/builds before replacing the working executable.
APT and moving vendor installers have explicit in-place failure contracts and
are never described as rollback-safe.

Read-only KVM, group, local Docker endpoint, sandbox daemon, systemd, and
Tailscale checks live in `lib/work-host.sh`. Host mutation stays in
`lib/install.sh`; neither layer is sourced during shell startup.

Uninstall requires recorded dotfiles ownership and validates every target
against the component's allowlisted roots. It rejects empty paths, HOME, broad
XDG roots, the checkout, and paths outside ownership.

## Theme feature

The theme feature owns the global theme state and the `@theme_*` and
`pane-colours[]` tmux options. Shells hold no theme state: program configs use
palette colors, and tmux maps them per window (see
[theme-system](theme-system.md)). When disabled, every tmux color resolves to
the terminal default and window themes are removed; program configs are
unchanged and take their colors from the terminal.

`bin/theme-switcher enable|disable` performs the explicit feature transition.
`bin/dotfiles-feature` provides the common feature preference interface.

## Agent-badge

The base tmux configuration has no agent-badge dependency. The Claude and Codex
marketplace packages are self-contained copies generated from `plugins/shared/`
and wire themselves when their session hook runs. Disabling agent-badge unwires
the live tmux fragments without deleting AI configuration or session data.

## Repository layout

```text
setup.sh, bootstrap.sh         installation entry points
entry/                         shell entrypoints (symlinked to ~/.bashrc etc.)
shell/env*.sh                  Layer 0 implementation
shell/init.sh                  Layer 1 loader
shell/tools/, shell/platform/  interactive aliases/functions and platform adapters
lib/runtime.sh                 side-effect-free command helpers
lib/config.sh                  CONFIG_MAP and APT package groups
lib/registry.sh                component inventory and ownership
lib/state.sh                   persistent state, lock, journal
lib/install.sh                 host mutation used by setup and installers
lib/work-host.sh               read-only work-host probes
installers/                    component-specific installation
configs/                       tracked configuration sources
bin/                           user and maintenance commands
themes/                        theme source data
plugins/shared/                agent-badge source of truth
plugins/agent-badge-*/         self-contained marketplace packages
```

## Test and deployment boundary

Automated tests create isolated HOME, XDG, PATH, temporary, and tmux roots.
Host-mutating commands are faked in unit tests. Hook tests use disposable
standalone repositories. Architecture jobs explicitly label ARM checks as
selection-only unless an ARM binary was actually executed.

Development and rollout practice is in [maintenance](maintenance.md). The
rationale behind much of this design is recorded in the completed
[September 2026 improvement plan](history/2026-09-improvement-plan.md).
