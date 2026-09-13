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
  shell/interactive/theme-env.sh and shell/theme-runtime.sh
  WSL adapter and independently installed agent-badge plugins
```

Login Bash follows `.bash_profile -> .bashrc -> .profile`. Non-login
interactive Bash follows `.bashrc -> .profile`. A startup-reading
non-interactive Bash stops after Layer 0; plain `bash -c` and Bash shebangs do
not read these files.

Zsh always reads `.zshenv`, which loads Layer 0, and reads `.zshrc` only for
interactive sessions. Layer 0 does not resolve themes, query tmux, define public
interactive commands, or remove externally owned functions.

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
- `theme.tsv`: global theme selection and overrides;
- `install-path`: fallback checkout discovery for flattened deployments;
- `transaction.tsv`: an interrupted artifact replacement journal;
- `backups/`: displaced user configuration.

These files have a version header, contain data only, are validated before use,
and are atomically replaced. Read-modify-write operations use a bounded
inter-process lock with conservative stale-lock recovery. Setup reconciles an
incomplete artifact journal before starting another install; verification
reports a pending journal as a failure.

Rebuildable theme output lives under
`${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/theme/`. The checkout is not the
machine-state database.

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
reporting, and uninstall. Each component records a binary/service check,
installation method, tier/feature, platform, supported architectures, ownership
roots, update contract, and uninstall paths where automated removal is safe.
`TOOL_TIER` records only cumulative membership. Composable, comma-separated
`TOOL_CAPABILITIES` records AI, RDP, Tailscale, and cloud membership. Docker and
sbx are ordinary work-tier components.

Companion executables are declared in `TOOL_COMPANIONS` and participate in
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

The theme feature owns global theme state, cache rendering, tmux theme hooks,
and launch-time adapters for Starship, FZF, bat, Delta, Neovim, btop, and
lazygit. When disabled:

- no theme state is resolved during shell startup;
- Starship, FZF, bat, and Delta use native defaults;
- btop and lazygit wrappers delegate directly;
- Neovim uses its built-in fallback;
- tmux removes theme hooks and generated styles while preserving session/window
  override values for a later re-enable.

`bin/theme-switcher enable|disable` performs the explicit feature transition.
`bin/dotfiles-feature` provides the common feature preference interface.

## Agent-badge

The base tmux configuration has no agent-badge dependency. The Claude and Codex
marketplace packages are self-contained copies generated from `plugins/shared/`
and wire themselves when their session hook runs. Disabling agent-badge unwires
the live tmux fragments without deleting AI configuration or session data.

## Repository layout

```text
entry/                         shell entrypoints
shell/env*.sh                  Layer 0 implementation
shell/init.sh                  Layer 1 loader
shell/interactive/             Layer 2 shell adapters
lib/runtime.sh                 side-effect-free command helpers
lib/config.sh                  configuration/package declarations
lib/registry.sh                component inventory and ownership
lib/state.sh                   persistent state, lock, journal
installers/                    component-specific installation
features are represented by their adapters and public commands
themes/                        theme source data
plugins/shared/                agent-badge source of truth
plugins/agent-badge-*/         self-contained marketplace packages
```

## Test and deployment boundary

Automated tests create isolated HOME, XDG, PATH, temporary, and tmux roots.
Host-mutating commands are faked in unit tests. Hook tests use disposable
standalone repositories. Architecture jobs explicitly label ARM checks as
selection-only unless an ARM binary was actually executed.

Development occurs in an isolated checkout. Performance measurement and owner
review precede adoption into the live symlink-target checkout. Integration,
configuration reconciliation, and host changes are separate actions described in
[maintenance and rollout](maintenance.md). The earlier implementation program is
retained as [history](history/2026-09-improvement-plan.md).
