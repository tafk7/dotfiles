# Setup redesign: implementation status

Every step is implemented except the end of 4.3: creating the schedule and
its trial run wait on the user. The [plan](setup-update-plan.md)
and [design](setup-update-redesign.md) are unchanged except as noted under
Deviations. Adoption on this machine waits until the whole plan is done (the
user's decision, 2026-10-26).

## Where things are

- Branch `setup-redesign` in the worktree `~/dev/dotfiles-setup`. Nothing is
  pushed. `git log main..setup-redesign` lists the commits.
- The live checkout (`~/dotfiles`), tmux, and HOME have not been changed,
  with one exception, which was reverted: early in Phase 0 a test-writing
  mistake overwrote `~/.local/bin/eza` and `~/.local/bin/btop`. Both were
  restored from their pinned releases, and their sha256 matches the ledger.
- Suite: all green apart from three failures that this host's environment
  causes and that predate the branch:
  - `agent-badge.sh` hard-codes `/usr/bin/tmux`.
  - `fresh-config.sh` needs some `vi`.
  - `tmux-compose-claude.sh` has a cleanup race (intermittent).

## Done

| Step | Summary |
|---|---|
| plan | Implementation plan |
| 0.1 | tmux.conf drops the inherited load guards |
| 0.2 | Environment layers: repo default, then `~/.shell.env`, then direnv (direnv runs last) |
| 0.3 | `reload` = fresh login shell in place; `reload --soft` |
| 0.4 | Ledger: package-manager ownership kept, zsh not hard-coded `ok`, snap path, clean versions |
| 0.5 | Docker's service is enabled only when it isn't already running |
| 0.6 | Per-component journals; bounded reconciliation; only the affected component is blocked |
| 0.7 | Explicit status checks inside setup phases |
| 0.8 | `--work` installs what the platform supports and skips sbx/KVM elsewhere; Docker checks are split from the sandbox checks |
| 0.9 | The fzf plugin's unverified-binary download hook is removed |
| 1.1 | Regression coverage |
| 1.2 | Outcome records and per-command exit precedence (`lib/outcomes.sh`) |
| 1.3 | Operation lock (`lib/operation.sh`) |
| 1.4 | Machine profile (`lib/profile.sh`) and `dotfiles profile` |
| 1.5 | Side-effect-free observation (`lib/observe.sh`); `--observe` on every installer |
| 1.6 | `dotfiles verify` on records; `check-updates --records` |
| 1.7 | Thin `dotfiles update` |
| — | sbx pinned at 0.49.2 (user request); kits built and validated with it |
| 2.1 | `versions.lock`: every download pinned with digests; eget tools current by binary digest; `eget.lock` gone |
| 2.2 | Pins for Node 24.22.1 (bundled npm 11.19.1), Rust 1.98.1, AWS CLI 2.37.12; `node` is a component; observation from `/` without rustup overrides |
| 2.3 | NVM and sbx move with their pins; sbx hold receipts (`holds.tsv`), one-time adoption question |
| 2.4 | One explicit install order in the registry, with needs, policy, install, configure; capability table and help from the registry; `--claude` selects only Claude |
| 2.5 | Configure steps (`lib/configure.sh`): AI settings, agent-badge registration and update, Pi settings, tailscaled (a masked unit is left alone) |
| 2.6 | `dotfiles apply`; dry run planned from observations; `--only` with blockers; `--reinstall[=X]`, `--overwrite-configs` |
| 2.7 | `deployed.tsv`; retirement of configs whose source left the manifest; gitconfig content check; honest `diff-config` |
| 2.8 | Three-way retirement of AI settings keys, with conflicts remembered |
| 2.9 | Editor plugins with the dev tier; vim-plug and plugins at their pins |
| 3.1 | Environment producer (`lib/env-producer.sh`, `lib/environment.sh`): owned and respected variables, PATH segments |
| 3.2 | tmux refresh: one server's environment, guards, PATH segments, session overrides reported, config, badge, theme, version check |
| 3.3 | Staleness: change events (`changes.tsv`), shell load records under `$XDG_RUNTIME_DIR`, process scan; verify's Running section |
| 3.4 | `dotfiles refresh`; one refresh at the end of every apply (`--no-refresh`) |
| 3.5 | `--upgrade`: APT only-upgrade with apt's simulated plan, held packages skipped; vendor updaters and `rustup self update`; `ai-update` wraps setup |
| 3.6 | Full update proven end to end (pin bump and environment change against a local remote) |
| 4.1 | `dotfiles bump` with a handler per kind of pin, both architectures, 14-day cool-down; the lock generator moved to `lib/lockgen.py` |
| 4.2 | `check-updates` covers every pin, with advisories, JSON, records, exit codes |
| 4.3 | The review prompt (`maintenance/dependency-review.md`); the schedule waits on the user |

## Waiting on the user

- **Push and merge.** The branch is unpushed; this machine's `main` runs it
  locally, ahead of `origin/main`.
- **The schedule (4.3).** A scheduled Claude job runs against the GitHub
  repository, so it needs this branch on `main` there first. Then the
  schedule (monthly review, weekly security check) is created and one manual
  run on a branch is checked for a reviewable pull request. Each step waits
  for the user's go-ahead.

## Follow-ups

- Done after adoption: enforced keys and per-machine defaults for the AI
  CLIs' settings ([ai-settings-per-machine.md](ai-settings-per-machine.md)).

- `tests/tmux-compose-claude.sh` can leave `nvim --embed` servers behind when
  its cleanup races, and they ignore SIGTERM; three were left on this host
  (killed with SIGKILL on 2026-10-26).
- The state lock (`lib/state.sh`) breaks a lock older than 2 seconds as
  stale, so under load two concurrent writers can both proceed and one
  update is lost: `tests/state.sh` "concurrent badge preference" failed once
  under the full suite on 2026-10-27, and passes alone.
- `dotfiles profile --propose` reads ownership from the ledger an older
  checkout wrote: Docker and Tailscale were recorded external though both
  are APT packages from their vendors' repositories, so `tail` was not
  proposed. Proposing from observations would fix it.

## Adopting a machine

This machine was adopted on 2026-10-26 (profile: tier work, all AI CLIs; the
dev tier's Neovim plugins; rustup left external; tailscaled left masked).
Left on it: pick up the commits since with a fast-forward and `dotfiles
apply`, settle Codex's settings (above), and start the agents.

The steps, for the next machine:

1. Move environment that agents and tmux need (anything set in
   `~/.shell.local` that is not interactive-only) to `~/.shell.env`.
2. Fast-forward `main` with git (an older checkout has no `dotfiles update`).
3. `dotfiles profile --propose`, then confirm. It reads only ledger rows
   dotfiles or the package manager installed; add what is wanted (`--add
   tail`, opt-outs) with `--no-apply`.
4. `dotfiles apply --dry-run`, review, then `dotfiles apply` in a terminal (the
   sbx hold question needs one on machines an older checkout set up; it ends
   with a refresh of the tmux server, which clears the guards from its global
   environment).
5. Adopt rustup if wanted: `dotfiles apply --only rust --reinstall=rust`.
6. Replace every shell and agent started before the pull: shells have no load
   records, and a git pull records no change event, so nothing lists them.
   Restarting the tmux server is simplest. In a shell kept, `reload` is still
   the old soft one: run it twice (the first defines the new one). A plain
   `exec "$SHELL" -l` is not enough: the new shell inherits the exported load
   guards and keeps the old environment. Codex's app-server daemon outlives
   tmux: `codex app-server daemon restart`.
7. `dotfiles verify -v`.

An older checkout held docker-sbx at 0.46.0 without a receipt, so the first
apply asks once whether to adopt the hold. Components recorded `unknown`
(present before the ledger) are preserved and not pinned until adopted with
`--reinstall=NAME`. Global npm packages stay with the previous Node release;
the installer names them.

## Deviations from the plan

- 1.6: `bin/verify` stays as it is for its `--tier`, `--all`, and capability
  modes, and isn't rewritten as a wrapper yet. `dotfiles verify` is the new
  record-based check.
- 2.1: `eget.toml` keeps its tags, because `--refresh` reads them. The check
  fails when they disagree with `versions.lock`, which is the only file
  installers read.
- 2.5: configure steps run after an install step that installed or found the
  component, never after a failed one.
- 2.6: `--only` refuses a component the run does not select, and skips the
  config phase.
- 2.9: Neovim's plugins come with the dev tier rather than a profile key
  (the user's decision, 2026-10-26), and ALE is gone: it ran a checkout's own
  linters on edit. A profile's `editor-plugins` line is ignored and dropped on
  the next save.
- Phase gates: the work continues in the worktree past the gates; adoption
  waits until the plan is complete.
