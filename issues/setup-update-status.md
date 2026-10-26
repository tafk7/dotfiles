# Setup redesign: implementation status

Paused 2026-10-26 at the user's request, partway through step 2.1. The
[plan](setup-update-plan.md) and [design](setup-update-redesign.md) are
unchanged except as noted under Deviations.

## Where things are

- Branch `setup-redesign` in the worktree `~/dev/dotfiles-setup`. 20 commits
  ahead of `main`, plus one work-in-progress commit for step 2.1. Nothing is
  pushed.
- The live checkout (`~/dotfiles`), tmux, and HOME have not been changed,
  with one exception, which was reverted: early in Phase 0 a test-writing
  mistake overwrote `~/.local/bin/eza` and `~/.local/bin/btop`. Both were
  restored from their pinned releases, and their sha256 matches the ledger.
- Suite: all green apart from three failures that this host's environment
  causes and that predate the branch:
  - `agent-badge.sh` hard-codes `/usr/bin/tmux`.
  - `fresh-config.sh` needs some `vi`.
  - `tmux-compose-claude.sh` has a cleanup race.

## Done

| Step | Commit | Summary |
|---|---|---|
| plan | `bce0194` | Implementation plan |
| 0.1 | `0ac6551` | tmux.conf drops the inherited load guards |
| 0.2 | `04c798a` | Environment layers: repo default, then `~/.shell.env`, then direnv (direnv runs last) |
| 0.3 | `c9ec428` | `reload` = fresh login shell in place; `reload --soft` |
| 0.4 | `d0fdcf9` | Ledger: package-manager ownership kept, zsh not hard-coded `ok`, snap path, clean versions |
| 0.5 | `b61a0eb` | Docker's service is enabled only when it isn't already running |
| 0.6 | `78fdf30` | Per-component journals; bounded reconciliation; only the affected component is blocked |
| 0.7 | `4ee2537` | Explicit status checks inside setup phases |
| 0.8 | `37b485e` | `--work` installs what the platform supports and skips sbx/KVM elsewhere; Docker checks are split from the sandbox checks |
| 0.9 | `4798736` | The fzf plugin's unverified-binary download hook is removed |
| 1.1 | `093e4dd` | Regression coverage |
| 1.2 | `2badbdc` | Outcome records and per-command exit precedence (`lib/outcomes.sh`) |
| 1.3 | `283fc0c` | Operation lock (`lib/operation.sh`); setup, uninstall-tool, and ai-config writes take it |
| 1.4 | `dc81e4c` | Machine profile (`lib/profile.sh`) and `dotfiles profile` |
| — | `1d23263` | rustc is recorded at its own path, not the rustup proxy |
| 1.5 | `a3197e4` | Side-effect-free observation (`lib/observe.sh`); `--observe` on every installer |
| 1.6 | `bc040b4` | `dotfiles verify` on records; `check-updates --records` |
| 1.7 | `78fbd17` | Thin `dotfiles update` |
| — | `5beafe1` | sbx pinned at 0.49.2 (user request) |

Commit hashes after `37b485e` changed in two `--autosquash` rewrites; use
`git log main..setup-redesign` for the current list.

## In progress: step 2.1, `versions.lock`

Committed as work in progress (`WIP: versions.lock`). Done so far:

- `versions.lock` exists: 48 rows covering:
  - eget tools, with archive and extracted-binary digests for both architectures;
  - neovim, tmux, the eget and nvm bootstraps, and vim-plug, with digests;
  - sbx 0.49.2.

  The extracted digests for eza and btop match this machine's ledger.
- `lib/versions.sh`: the parser (`versions_row`, `versions_field`) and
  validation (`versions_problems`).
- `tests/eget-selection.py` reads and writes `versions.lock`. `--refresh`
  computes the extracted-binary identity and keeps the non-eget rows. The
  check passes.
- `lib/config.sh` loads the sbx, neovim, tmux, eget, and nvm pins from the lock.

Remaining for 2.1:

1. `install_eget_tools`:
   - read the row from `versions.lock` instead of `eget.toml` and `eget.lock`;
   - treat a binary whose sha256 equals the lock identity as current, and drop
     the `--version` substring match;
   - refuse an extracted binary that doesn't match the identity.
2. `lib/observe.sh`: an eget tool's identity is `tag:WANT` when its sha256
   equals the lock identity, not when it matches the ledger hash.
3. Add sha256 verification of the eget tarball (`install-eget.sh`), the nvm
   `install.sh` (`install-nvm.sh`), and `plug.vim`
   (`bin/install-editor-plugins`), all from the lock.
4. `git rm eget.lock`. Update the tests that write a fake `eget.lock`
   (`eget-staging.sh`, `regression-coverage.sh`) to write lock rows.
5. Have `setup.sh` validate the lock (`versions_problems`) in
   `phase_verify_system`. Add `tests/versions-lock.sh` (parsing, duplicates,
   malformed rows, missing arch rows, both arch-independent and per-arch rows).
6. Docs: supply-chain table, customization "adding a tool", testing,
   architecture module list, eget-selection docstring (done).

Then: steps 2.2 to 2.9, Phase 3, and Phase 4, as planned.

## Waiting on the user

- **Adoption:** Phases 0 and 1 have not been adopted on this machine. Phase 0's
  adoption list:
  1. Fast-forward `main`.
  2. Move `PROJECTS_DIRS` (and any `EDITOR`) from `~/.shell.local` to
     `~/.shell.env`.
  3. Run `./setup.sh --full --tail`.
  4. Restart the tmux server once.
  5. Run `dotfiles verify`.

  Phase 1 adds:
  1. `dotfiles profile --propose`, then confirm.
  2. `dotfiles verify -v`.
  3. `dotfiles update` with nothing upstream.
- **Kits:** not yet built against sbx 0.49.2. Building them uses Docker, so it
  waits for approval.

## Findings on this machine (read-only)

- docker-sbx 0.49.2 is installed and not held. The pin is now 0.49.2, so setup
  will add the hold. The planned one-time hold-adoption prompt (step 2.3) will
  have no existing hold to adopt.
- tailscaled is masked, deliberately, until a vulnerability is patched.
  `dotfiles verify` reports it as a health finding (exit 2), which doesn't fail
  `update`.
- `ai-config --check` reports drift in `~/.codex/config.toml` and a Claude
  badge plugin version mismatch.
- The ledger records rust as unowned at the rustup path. That came from the
  old path resolution, and the next setup run corrects the path.

## Deviations from the plan

- 1.6: `bin/verify` stays as it is for its `--tier`, `--all`, and capability
  modes, and isn't rewritten as a wrapper yet. `dotfiles verify` is the new
  record-based check. `check-updates` gained `--records`, and
  `ai-config --check` is consumed by exit status.
- 2.1: `eget.toml` keeps its tags, because `--refresh` reads them. The check
  fails when they disagree with `versions.lock`, which is the only file
  installers read.
- Phase gates: the work continues in the worktree past the gates, and
  adoption waits for the user's go-ahead.
