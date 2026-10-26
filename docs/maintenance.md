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
files (`~/.shell.env`, `~/.shell.local`, `~/.gitconfig.local`). To have the
pre-commit hook enforce that, point `DOTFILES_DENYLIST` at an untracked file
listing those words, one per line. Without the variable the hook (and the
Claude invariant guard rules in `.agents/invariants.json`) read
`~/.config/dotfiles/denylist` when it exists. Check the whole tree with
`git grep -n -i -w -F -f <(grep -vE '^[[:space:]]*(#|$)' "$DOTFILES_DENYLIST")`.

## Updates and ownership

`dotfiles update` brings a machine up to its checkout's upstream: it takes
the operation lock, checks that this checkout is the install path, on a branch
with an upstream and without uncommitted changes, fetches and shows the
incoming commits, fast-forwards, re-executes the pulled code, applies the
machine profile (`dotfiles apply`), and verifies. An ahead-only branch skips the pull;
a diverged one stops it. Configs removed upstream are retired by the apply
(see [customization](customization.md#adding-a-config-file)).

`--upgrade` (on `update`, `apply`, or `setup.sh`) also moves what is not
pinned, between the component and config phases: the selection's installed
APT packages through `apt-get install --only-upgrade --no-remove`, after
showing apt's simulated transaction (dependencies outside the selected names
included) and skipping held packages; the AI CLIs and Pi through their
updaters; and rustup itself. Pinned components, Node, and the Rust toolchain
move only with `versions.lock`. Upgraded components reach the ledger, and the
run is in the setup log.

`dotfiles refresh` changes running processes only. It targets one tmux
server (`$TMUX`'s, else the one `DOTFILES_TMUX_SERVER` names, else the
default): the global environment gets the managed variables from the
environment producer (`lib/env-producer.sh`, which reads the repo defaults and
`~/.shell.env` but never direnv or user startup files) and loses the load
guards and last time's PATH segments; a session that overrides a managed
variable is reported, not changed; then `~/.tmux.conf` is sourced, the badge
rewired, and the theme applied. A server older than the installed tmux is a
health finding. It then reports staleness from persistent state: shells that
loaded before the last change to shell startup (a soft reload stays stale),
shells possibly stale after a hand edit of `~/.shell.local` or `~/.shell.env`,
and programs started before their binary or settings changed. Apply ends with
one refresh (`--no-refresh` skips it), and setup leaves tmux and the theme to
it.

`dotfiles apply` runs setup with the profile's flags. Its dry run is a plan
built from observations: it names only components to install, move to their
pin, or repair, configure steps with work to do, and configs that differ, and
marks what it could not check as Unknown. `--only X,Y` narrows the run to
those components and blocks one whose needs are not installed;
`--reinstall=X,Y` reinstalls only those.

To move a pin, use `bin/check-updates`, bump the pin, and run `dotfiles apply`. Direct `eget --download-all` bypasses platform/tier selection, ownership
recording, companion handling, and staged replacement. `check-updates` exits 1
for failed lookups, 2 for updates found with `--outdated`, and 0 otherwise.

Only a successful installation establishes ownership. A binary that setup
skipped because it already existed is not owned, even under `~/.local/bin`, and
recorded ownership only holds for the same resolved path. Self-updating
vendor CLIs (Claude, Codex, opencode) are the exception: they may move within
their ownership roots, and setup records the new path. Adopting an existing
local install requires `--reinstall` (or `--force`). AI installers keep their vendor-specific
contracts ([supply chain](supply-chain.md)).

Ledgers written before ownership was recorded explicitly may contain ownership
inferred from location. Check `uninstall-tool --dry-run NAME` before trusting
an old record, and don't blanket-adopt or remove unrecorded local tools.

## Setup logs

Each setup run writes `~/.local/state/dotfiles/logs/setup-<UTC time>.log`
(`-dry-run` suffix for previews; `latest.log` links the newest; the last
`DOTFILES_LOG_KEEP`, default 30, are kept). The header names the command,
checkout revision with its uncommitted-file count, and host. The body is the
whole transcript without color codes. The footer gives the exit status and the
ledger rows the run changed, timestamps aside. Standalone installer runs are
not logged; `bin/ai-update` runs setup, so it is. `DOTFILES_SETUP_LOG=0` disables the log;
the test harness sets it.

## Recovery

One state-changing command runs at a time: setup, `uninstall-tool`, and
`ai-config` writes hold an operation lock (`operation.lock` in the state
directory), and a second one exits 75 naming the holder. Only the top-level
command holds it; a dotfiles command it starts, such as `ai-config` from an
installer, joins the operation instead. Help, `--check`, and `--dry-run` runs
take no lock. Each artifact replacement writes a journal first. When a replacement fails,
setup makes one bounded attempt to reconcile it: if the artifact now at the
target runs, it is recorded and the journal removed. Otherwise the journal is
kept, and it blocks further replacements of that component only, until setup
reconciles it; the rest of the run proceeds and the run reports failure.
`bin/verify` reports a pending journal as a failure. Recovery checks the
recorded artifact itself, not whatever binary is on PATH. If that artifact
cannot run, diagnose the paths before retrying.

A replacement can commit before its ledger write fails, so the new artifact may
already be active while the journal remains. Multi-binary components are
validated together and then promoted one executable at a time, so an update
across several executables is not atomic as a group.

## Compatibility code

Migration code is removed once every machine has migrated. Nothing reads a
checkout's `generated/` directory any longer; an old checkout's copy is ignored
and safe to delete.

## Optional editor and badge setup

Editor plugins are opt-in: enroll them with `dotfiles profile --add
editor-plugins` (or `setup.sh --editor-plugins`), and setup runs
`bin/install-editor-plugins` as Neovim's configure step. It installs the
pinned vim-plug revision, installs missing plugins, and moves each plugin
checkout to the commit `configs/init.vim` pins; a vim-plug that dotfiles did
not install, and a checkout with local changes, are left alone and reported.
`--check` (and setup's dry run) reports what would change, and
`dotfiles verify` lists anything off its pin. Ordinary editor startup never
touches the network.
Existing plugin and undo directories under Neovim's config root keep working;
fresh profiles use XDG data and state.

Agent-badge requires `jq`, Bash, tmux, and GNU `timeout`
([dependencies](../plugins/shared/README.md#install)). Setup installs `jq`
without sudo when a supported AI CLI is selected with badges enabled.
Verification reports a missing `jq`, and the session hook prints a diagnostic
instead of misreading payloads. Hooks never install dependencies.
