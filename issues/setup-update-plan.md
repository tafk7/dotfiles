# Implementation plan: setup, update, and refresh

Implements [the design](setup-update-redesign.md). The design says *what*;
this says *in what order*, at the level of one commit per step. Section names
in parentheses point into the design.

## Ground rules

- **Worktree.** Work on branch `setup-redesign` in a separate worktree
  (`git worktree add ~/dev/dotfiles-setup -b setup-redesign`). Never run setup
  against the live HOME from it ([maintenance](../docs/maintenance.md)).
- **One step, one commit.** Each step lands with the full suite green,
  shellcheck clean, and `git diff --check` clean. Docs,
  `shell/shortcuts-index.tsv`, and comments change in the same commit as the
  behavior they describe.
- **Tests first.** A step that changes behavior starts with a failing test, or
  with coverage of today's behavior when it must not change. The harness's
  isolated HOME and mutation spies (`tests/lib/harness.sh`) are the default.
- **Phase gates.** At the end of each phase: fast-forward `main`, adopt it on
  this machine (each phase's "Adopt" list), and only then start the next.
- **Protected files.** Edits to `entry/*` and other `$HOME`-linked files are
  intentional by construction here; commit them with `ALLOW_PROTECTED=1` and
  say so in the message.
- **Compatibility.** Existing `setup.sh` flags keep working throughout.
  Nothing removes a flag or changes a tier's meaning except the `--work`
  decision (step 0.8).

## Phase 0: bounded fixes

Fixes that stand alone and do not wait for the new contracts.

| Step | Change | Proven by |
|---|---|---|
| 0.1 | `configs/tmux.conf` unsets `_DOTFILES_BASE_ENV` and `_DOTFILES_ENV_LOADED` from the global environment on load. | tmux test: a new pane runs `env.sh` (sees a changed LESS) after a reload. |
| 0.2 | Environment layers (Refresh, "Environment layers"): `env.sh` assigns owned variables unconditionally; `~/.shell.env` is sourced after it in every shell; `entry/profile.sh` runs `env.sh` before the direnv step. README and customization docs explain `.shell.env` versus `.shell.local`. | Shell matrix (bash, zsh, interactive and not): repo default, `.shell.env` override, `.envrc` override wins; startup benchmark within budget. |
| 0.3 | `reload` becomes `exec $SHELL -l` (history saved, directory kept, refuses with jobs); `reload --soft` keeps today's behavior with every guard cleared. | Shell tests for both modes and the jobs refusal. |
| 0.4 | Ledger accuracy: apt skips keep `package-manager`; zsh no longer hard-coded `ok`; snap shims resolved; version strings cleaned (ANSI, banners) by per-tool rules. | State and registry tests with fixture binaries for btop, eza, gcloud-via-snap. |
| 0.5 | Enable and start docker only when it is not already enabled and active. | systemctl stub records no call on a ready host. |
| 0.6 | On a failed replacement, attempt bounded reconciliation; clear the journal only after the result is validated and recorded; otherwise keep it and block only the mutations it affects. | `tests/transaction-failures.sh` extended: resolved failure continues; unresolved keeps the journal. |
| 0.7 | Audit `fn \|\| FAILED=true` paths; every fallible command gets an explicit status check. | `tests/install-failures.sh` cases for the three known unchecked commands. |
| 0.8 | `--work` on platforms where sbx does not apply: skip sbx and its KVM/builder steps, record not-applicable; split Docker readiness out of the work-host checker so Docker is still verified. README and the work-tier issue updated. | Selection fixtures for WSL and 22.04; verify fixtures with Docker selected and sbx not applicable. |
| 0.9 | Inspect the pinned fzf plugin's installer; remove `fzf#install()` if it fetches an unverified binary. | Neovim test still finds fzf from PATH. |

**Adopt:** pull into the live checkout; move PROJECTS_DIRS (and any EDITOR) to
`~/.shell.env`; `./setup.sh --full --tail`; restart the tmux server once, so
the inherited guards are gone; `bin/verify --installed`.

## Phase 1: profile, observation, verify, thin update

| Step | Change | Proven by |
|---|---|---|
| 1.1 | Regression coverage before anything moves: per-tool AI flags, external installs, unsupported platforms, custom XDG roots, moved and downgraded pins, partial failure. | The new tests pass against today's code. |
| 1.2 | Outcome records and classes (Outcomes): a small library that emits `class, section, subject, message` and computes the per-command exit. | Unit tests for precedence and "converged requires complete". |
| 1.3 | Operation lock (Operation lock): re-exec under `flock -o`, run id and holder pid in the lock file, joining by `DOTFILES_OPERATION`. Adopted by `setup.sh`, `uninstall-tool`, and `ai-config` writes. | Concurrent setup refused; a surviving background child does not hold the lock; a nested participant joins. |
| 1.4 | Machine profile (Machine profile): schema, atomic write, merge rules, `ai.exclude`, opt-outs; setup merges its flags (never on `--dry-run`); `dotfiles profile` show, add, remove, tier, propose. | Profile tests for merge, removal, exclusion, dry-run, and ledger-derived proposal. |
| 1.5 | Component observation (Component observation): engine observation for eget and apt; `--observe` for every installer, branching before provisioning; per-component probe rules. | Mutation spies show no writes during observation; exit 3 on unreadable state. |
| 1.6 | `bin/dotfiles` and `dotfiles verify` (Commands): sections built on records; `verify`, `diff-config`, `check-updates`, and `ai-config --check` emit records and become wrappers; `-v`. | Verify fixtures per section and exit code; wrappers keep their old output. |
| 1.7 | Thin `dotfiles update` (Update): lock, preconditions, fetch and show, `pull --ff-only`, re-exec, today's setup with the profile, verify. Help states what it does not do yet. | Update tests against a local bare remote: dirty, diverged, ahead-only, detached, worktree, normal. |

**Adopt:** `dotfiles profile --propose`, confirm; `dotfiles verify -v`;
`dotfiles update` with nothing upstream, then with one trivial upstream commit.

## Phase 2: apply, versions, config state

| Step | Change | Proven by |
|---|---|---|
| 2.1 | `versions.lock` (Versions and artifacts): schema, bash parser, validation; every existing pin moved (eget tags and digests, neovim, tmux, sbx, eget, nvm, vim-plug) with extracted-binary digests and bootstrap digests; `eget.toml` generated or validated from it. | Lock validation tests; CI check; installs unchanged on fixtures. |
| 2.2 | New pins: Node with its bundled npm, the Rust toolchain, aws-cli; isolated observation (rustup from a neutral directory, no auto-install). | Installer and observation tests, including an independently upgraded npm and a project `rust-toolchain`. |
| 2.3 | nvm and sbx converge on moved pins; sbx hold receipts and the one-time adoption prompt. | Moved-pin fixtures; hold with and without receipt. |
| 2.4 | Registry: explicit order, `needs`, `policy`, `configure`; tier loops driven by the registry; capabilities and help generated; selection honors per-tool AI. | `tests/setup-selection.sh` snapshot unchanged except intended fixes. |
| 2.5 | Configuration steps extracted from installer early exits (AI settings, badge, plugin update, services), run whether or not the binary changed. | A current, external Claude still gets its settings and badge checked. |
| 2.6 | Apply from observations, in two phases (components, configs); `dotfiles apply`; projected dry-run with `unknown`; `--only` with blockers; `--reinstall`, `--overwrite-configs`, `--force` as both. | Dry-run on an up-to-date fixture prints no actions; `--only` reports unmet needs. |
| 2.7 | Config state and retirement (Config state and retirement): `deployed.tsv`, exact-identity retirement under approved roots, per-entry records, backups; gitconfig content check; honest `diff-config`. | Retirement tests: removed entry retired; redirected link kept; partial failure keeps earlier records. |
| 2.8 | AI three-way retirement in `lib/config_files.py`: leaf records, conflicts remembered, Pi's seed-once settings exempt. | `tests/ai-config.py` cases for removed, edited, and re-added keys. |
| 2.9 | Editor plugins under profile enrollment; plugins and vim-plug converge to their pins. | Editor-plugin test with a moved commit. |

**Adopt:** `dotfiles apply --dry-run` shows nothing on this machine; adopt
the sbx hold when prompted; `dotfiles apply`; `dotfiles verify`.

## Phase 3: refresh and full update

| Step | Change | Proven by |
|---|---|---|
| 3.1 | Environment producer: bounded script, managed variable list, PATH segment tracking. | Producer never runs direnv or user startup; machine overrides survive; removed PATH segments go. |
| 3.2 | tmux refresh: one targeted server, global environment, session overrides reported, `DOTFILES_DIR`, `source-file`, badge, theme, server version check. | tmux tests with a session override and a version mismatch stub. |
| 3.3 | Staleness: change events recorded by operations; shell records in the runtime directory; process scan; "possibly stale"; verify's running section. | A second refresh still lists a stale process; a soft reload stays stale; pid reuse is not mistaken for the same shell. |
| 3.4 | `dotfiles refresh`; apply's trailing refresh with `--no-refresh`. | Refresh runs once per command. |
| 3.5 | `--upgrade`: installer `--update` operation; apt `--only-upgrade --no-remove` with the simulated transaction in the plan; `rustup self update`, `pi update`; `ai-update` becomes a wrapper. | apt stub transcripts; upgrades logged and recorded in the ledger. |
| 3.6 | Full `dotfiles update`: components, upgrades, configs, refresh, verify, report. | End-to-end update against a local remote with a pin bump and an environment change. |

**Adopt:** `dotfiles update` on a real upstream change that touches the
environment; check the stale-shell list; `dotfiles update --upgrade --dry-run`.

## Phase 4: maintenance

| Step | Change | Proven by |
|---|---|---|
| 4.1 | `dotfiles bump` with per-kind handlers (GitHub releases, Node, Rust, aws-cli, git commits, sbx), both architectures, 14-day cool-down; the lock generator moves out of `tests/`. | Bump tests against recorded release fixtures; refusal inside the cool-down. |
| 4.2 | `check-updates` covers every pinned row in JSON and exit code, plus advisory lookup. | `tests/check-updates.sh` extended. |
| 4.3 | The scheduled review: its prompt checked into the repo (monthly review, weekly security check), then the schedule created, with confirmation at that time. | One manual run on a branch produces a reviewable pull request. |

## Sizing and risk

Roughly 9 commits in Phase 0, 7 in Phase 1, 9 in Phase 2, 6 in Phase 3, and 3
in Phase 4. Phase 0 and Phase 1 are the immediate payoff: correct environments
in new panes and one-command updates. Phase 2 is the largest and riskiest,
because the registry-driven tier loops replace hard-coded installation order;
step 1.1's coverage and the selection snapshot are what make it safe.

Known hazards:

- The live checkout is what every shell runs. Adopt only at phase gates, from
  `main`, never mid-phase.
- Step 0.2 reorders shell startup for every shell, including agents' tool
  calls; the shell matrix and startup benchmark gate it.
- The tmux server must be restarted once after Phase 0 to drop inherited
  guards; until then, new panes may still be stale.
- Profile migration (1.4) and the sbx hold adoption (2.3) are the only steps
  that ask questions on an existing machine; both are one-time.
