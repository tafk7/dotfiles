# Maintenance and rollout

Develop changes in an isolated checkout. Shell RC files on installed machines
are symlinks into the active checkout, so editing that checkout changes what
the next shell or tool invocation loads immediately.

## Before adoption

1. Preserve the base revision and make changes in a separate clone or worktree.
2. Run the isolated behavioral tests described in [testing](testing.md).
3. Compare startup against the preserved base with at least 30 interleaved
   samples per shell/context. Report median, p95, absolute milliseconds, and
   percentage changes, with themes both enabled and disabled.
4. When available, also run the installed-tool benchmark. It uses the actual
   local tools with a disposable HOME and authorized disposable direnv project.
5. Present changes, measurements, limitations, and the proposed live rollout.
   The owner decides whether a performance regression is acceptable before
   adoption. Passing the automated threshold does not replace that decision.

The benchmark's regression threshold is both 10 ms and 15% at the median,
with a two-second catastrophic limit. Smaller changes, tail latency, repeated
invocation frequency, and host noise still belong in the report. Run performance
measurements without concurrently running the test suite or other benchmarks.

After approval, integration into the active checkout and configuration/state
reconciliation are distinct actions. Preview the selected setup command first.
Do not run setup against the real HOME from a development checkout: it would
redirect live symlinks and record the development checkout as the install path.
Package/service changes require their own intentional selection.

## Updates and ownership

Use `bin/check-updates`, update the relevant release pin, and rerun setup with
the component's tier. Direct `eget --download-all` bypasses platform/tier
selection, ownership tracking, companion handling, and staged replacement.
Update reporting exits 1 for failed lookups, 2 for updates found with
`--outdated`, and 0 otherwise. JSON mode emits `[]` for no matching rows.

A skipped binary in a local prefix is not automatically owned. Recorded
ownership is preserved only for the same resolved path; an actual successful
installation establishes ownership. Eget's explicit `--force` behavior can
install a pinned local copy over a system-provided command. Custom native
installers preserve external commands; local unrecorded installations require
`--force` for adoption. AI installers retain their vendor-specific contracts.

Older ledgers may contain ownership inferred from location. They remain readable;
this refinement cannot reconstruct their provenance. Inspect `uninstall-tool
--dry-run NAME` and the component's original installer before relying on an old
ownership record. Do not blanket-adopt or remove unrecorded local tools.

An interrupted artifact journal blocks another replacement until reconciled.
Run one setup/update operation at a time; this is not a concurrent package manager.
Failed moves and ledger writes propagate failure and retain the journal.
Recovery verifies the recorded artifact directly, not an unrelated PATH binary.
If the artifact cannot run, preserve the journal and diagnose the paths before
retrying. A replacement that committed before a ledger failure may already be
active; its journal is retained for reconciliation. Multi-binary components are
prevalidated and promoted one executable at a time, not as a group-atomic update.

## Compatibility retirement

Legacy generated-state readers remain until every work/personal machine has
valid XDG theme state and checkout discovery state. On each machine, verify
`theme.tsv` through `bin/verify --installed` and confirm `install-path` names its
intended checkout. Record host and migration completion privately. Remove the
readers and their migration tests only after the complete fleet is accounted for.

The Ubuntu 20.04/glibc-2.31 Neovim branch is removed: that release is outside the
supported platform matrix. `--work` still includes sbx/KVM; changing this public
selection is tracked as a [separate decision](../issues/work-tier-sandbox-boundary.md).

## Optional editor and badge setup

After `setup.sh --dev`, run `bin/install-editor-plugins` explicitly to bootstrap
the pinned vim-plug revision and install the configured plugins. Ordinary editor
startup remains offline. Existing vim-plug files are preserved. Existing plugin
and undo directories under Neovim's config root continue to be used; fresh
profiles use XDG data for plugins and XDG state for undo. Directory relocation
is not required for adoption.

Agent-badge requires `jq`, Bash, tmux, and GNU `timeout`; see its
[dependency instructions](../plugins/shared/README.md#install). Setup installs jq
without sudo when selecting Claude/Codex with badges enabled and jq is absent.
Verification reports missing jq, and the session hook emits a diagnostic rather than
silently misinterpreting payloads. Dependency installation is never a hook action.
