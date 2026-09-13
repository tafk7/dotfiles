# One-time ownership migration

This directory is temporary. Delete the entire directory after all personal/work
systems have migrated. Nothing in setup, shell startup, or CI loads it.

Use it for tools recorded as `unknown / present` by configuration reconciliation
before installation ownership was tracked. It changes only the component ledger
and creates a private backup beside it. It does not install tools, execute vendor
CLIs, source NVM, change configuration, or switch the active checkout.

From the checkout containing this script:

```bash
# Preview all unclaimed installations; no writes.
bash migrations/2026-09-ownership/adopt.sh

# Review the same plan and type "adopt" to confirm.
bash migrations/2026-09-ownership/adopt.sh --apply

# Alternatively select only installations you recognize.
bash migrations/2026-09-ownership/adopt.sh --apply eza uv neovim tmux
```

`--apply --yes` is available for explicitly authorized unattended runs. Confirm
only installations you want dotfiles to manage, including future uninstall.
Filesystem checks cannot prove which installer originally created a binary;
your confirmation supplies that authority. Already-managed and explicitly external
records remain unchanged. Missing, shadowed, or out-of-root installations block
the batch; select an eligible subset to proceed without those entries.
The existing registry exception for agent/editor-private ripgrep also applies:
that incidental PATH entry does not block adoption of a valid `~/.local/bin/rg`.

NVM is validated as a nonempty, user-owned `nvm.sh` and recorded by its install
directory. Rust validates its rustc/cargo/rustup launchers. Versioned agent
launchers are resolved within their declared user-local roots. If the resolved
path changed since discovery, the old version string is cleared rather than
attributed to the new artifact. Executable permissions and file hashes are
checked without invoking installed programs.

A missing companion such as uvx is reported but does not block adoption of an
existing uv. After adoption, the normal `setup.sh --bash` selection can repair
that component. Adoption itself downloads nothing.

Run one migration/setup/update operation at a time. The apply step locks the
state directory, rechecks the ledger and artifacts, writes a complete staged
ledger, and replaces it atomically. A pending artifact transaction blocks the
migration. Rerunning an already completed selection is a no-op.

The printed `components.before-ownership-2026-09.tsv.*` file is an exact ledger
backup. To undo adoption, stop other setup/update operations and restore that
backup over `components.tsv` before making further ledger changes. No tool or
configuration rollback is needed. Keep these per-machine backups outside Git.

Run the disposable tests with:

```bash
bash migrations/2026-09-ownership/test.sh
```

After applying on a machine, run `bin/verify --installed`. Existing unrelated
warnings and missing companion binaries may still require attention.
