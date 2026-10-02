# Maintenance

## Developing changes

Installed shell rc files are symlinks into the active checkout, so editing that
checkout changes the next shell or tool invocation immediately. Develop in a
separate clone or worktree, run the [tests](testing.md), and compare startup
time against the base revision before adopting a change into the live checkout.

Don't run setup against the real HOME from a development checkout. That would
point the live symlinks at it and record it as the install path. Adopting the
code and reconciling config/state (`./setup.sh --config` or a tier) are separate
steps; preview the setup command with `--dry-run` first.

The repository is public. Keep employer names and internal hosts in untracked
files (`~/.shell.local`, `~/.gitconfig.local`). To have the pre-commit hook
enforce that, point `DOTFILES_DENYLIST` at an untracked file listing those words,
one per line; check the whole tree with
`git grep -n -i -w -F -f <(grep -vE '^[[:space:]]*(#|$)' "$DOTFILES_DENYLIST")`.

## Updates and ownership

Use `bin/check-updates`, bump the pin, and rerun setup with the component's
tier. Direct `eget --download-all` bypasses platform/tier selection, ownership
recording, companion handling, and staged replacement. `check-updates` exits 1
for failed lookups, 2 for updates found with `--outdated`, and 0 otherwise.

Only a successful installation establishes ownership. A binary that setup
skipped because it already existed is not owned, even under `~/.local/bin`, and
recorded ownership only holds for the same resolved path. Self-updating
vendor CLIs (Claude, Codex, opencode) are the exception: they may move within
their ownership roots, and setup records the new path. Adopting an existing
local install requires `--force`. AI installers keep their vendor-specific
contracts ([supply chain](supply-chain.md)).

Ledgers written before ownership was recorded explicitly may contain ownership
inferred from location. Check `uninstall-tool --dry-run NAME` before trusting
an old record, and don't blanket-adopt or remove unrecorded local tools.

## Recovery

Run one setup or update at a time; this is not a concurrent package manager.
An interrupted artifact journal blocks further replacements until setup
reconciles it, and `bin/verify` reports it as a failure. Recovery checks the
recorded artifact itself, not whatever binary is on PATH. If that artifact
cannot run, the journal is kept; diagnose the paths before retrying.

A replacement can commit before its ledger write fails, so the new artifact may
already be active while the journal remains. Multi-binary components are
validated together and then promoted one executable at a time, so an update
across several executables is not atomic as a group.

## Compatibility code

Migration code is removed once every machine has migrated. Nothing reads a
checkout's `generated/` directory any longer; an old checkout's copy is ignored
and safe to delete.

Whether `--work` should keep including sbx/KVM is an
[open decision](../issues/work-tier-sandbox-boundary.md).

## Optional editor and badge setup

`bin/install-editor-plugins` bootstraps the pinned vim-plug revision and
installs Neovim plugins, so ordinary editor startup never touches the network.
Existing plugin and undo directories under Neovim's config root keep working;
fresh profiles use XDG data and state.

Agent-badge requires `jq`, Bash, tmux, and GNU `timeout`
([dependencies](../plugins/shared/README.md#install)). Setup installs `jq`
without sudo when a supported AI CLI is selected with badges enabled.
Verification reports a missing `jq`, and the session hook prints a diagnostic
instead of misreading payloads. Hooks never install dependencies.
