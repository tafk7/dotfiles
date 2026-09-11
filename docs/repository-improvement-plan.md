# Dotfiles improvement plan

Status: approved direction; implementation pending.

This plan turns the September 2026 repository review into an ordered implementation
program. The goal is not merely to fix individual defects. It is to make the repository
smaller in its failure surface, honest about what it supports, and easy to run in two
distinct contexts:

1. a fundamental core for login shells, scripts, CI, and AI workers; and
2. the full interactive environment, including coordinated themes and optional
   integrations, enabled by default for normal installations.

The governing rule is:

> Included by default does not mean structurally inseparable.

Themes and integrations may enrich the default experience, but the fundamental shell,
installer, tmux, Git, SSH, and editor paths must remain correct when any optional feature
is disabled, absent, or broken.

## Decisions already made

- Ubuntu and WSL remain the supported operating systems.
- Both `x86_64` and `aarch64` are supported architectures.
- ARM support must be preserved even though the current development machine cannot
  execute ARM binaries natively.
- The coordinated theme system remains in this repository and remains enabled by
  default.
- The theme system becomes an isolated default feature rather than a prerequisite of
  the fundamental core.
- AI CLIs, agent-badge, the WSL SSH bridge, and xrdp remain optional integrations.
- Agent-badge is installed by default when a supported AI CLI is selected, but tmux must
  not depend on it.
- Existing public commands should retain compatibility unless a command is demonstrably
  broken, misleading, or unsafe.
- Correctness and safety land before directory rearrangement or cosmetic cleanup.
- Implementation work happens outside the live symlink-target checkout and must not
  mutate the active user environment until a deliberate rollout step.

## Non-goals

- Supporting macOS, BSD, or arbitrary Linux distributions.
- Replacing Bash with another implementation language during this work.
- Splitting the theme system into a separate repository.
- Rewriting every mature configuration merely because a newer ecosystem tool exists.
- Adding abstractions without a concrete invariant or duplication they eliminate.
- Claiming supply-chain guarantees that upstream release processes cannot support.

## Target architecture

### Runtime layers

The runtime will have three explicit layers.

```text
Layer 0: fundamental environment
  locale, XDG paths, PATH, editor, project environment, direnv activation
  no prompt, aliases, public interactive functions, theme resolution, plugin wiring,
  or TUI setup

Layer 1: interactive core
  shell options, history, completion, general tool aliases/functions, prompt fallback
  works without themes, AI CLIs, agent-badge, WSL bridge, or desktop components

Layer 2: default and optional features
  theme                 enabled by default
  agent-badge           enabled with supported AI CLI installs unless opted out
  WSL SSH bridge        explicit per-machine opt-in
  xrdp                  explicit installer opt-in
```

Non-interactive shells and AI workers stop after Layer 0. Interactive shells load Layer
1 and then enabled Layer 2 features. A feature may add behavior, but it may not make a
Layer 0 or Layer 1 command fail when the feature is absent.

### Installation dimensions

Package tiers and features remain separate concepts.

```text
Package tier:  config -> bash -> dev -> work
Features:      theme (default on), AI tools, agent-badge, WSL bridge, xrdp
Architecture:  x86_64 or aarch64
Platform:      native Ubuntu or WSL
```

The tier answers “how much software is installed.” A feature answers “which optional
behavior is enabled.” Platform and architecture decide whether an installation is
applicable and which artifact is selected.

Normal behavior remains concise:

```bash
./setup.sh --bash               # bash tier + default theme feature
./setup.sh --dev --ai           # dev tier + theme + AI CLIs + agent-badge
./setup.sh --bash --no-theme    # fundamental/headless-friendly environment
./setup.sh --ai --no-agent-badge
```

Exact flag names may be adjusted during implementation, but feature selection must be
orthogonal to package tiers and must have an inspectable final state.

### Repository boundaries

The first implementation should establish loading boundaries before moving many files.
Once behavior is covered by tests, theme-specific code and data can be grouped under a
clear feature directory.

Target shape:

```text
entry/                         shell entrypoints only
shell/
  core/                        Layer 0, safe for non-interactive shells
  interactive/                 Layer 1, Bash/Zsh interactive behavior
  platform/                    platform adapters
features/
  theme/
    bin/                       theme implementation
    lib/                       resolution/rendering helpers
    shell/                     interactive theme runtime adapter
    themes/                    palette data
plugins/
  shared/                      agent-badge source
  agent-badge-claude/          marketplace package
  agent-badge-codex/           marketplace package
generated/
  compatibility/               temporary migration shims, removable after upgrade
```

Public commands such as `bin/theme-switcher` may remain as thin compatibility entrypoints
if moving their implementation materially improves the boundary. Compatibility wrappers
must contain no business logic.

### Feature contract

Each feature will answer the same questions:

- Is it enabled?
- Is it applicable on this platform and architecture?
- What does setup install or generate?
- What does runtime sourcing load?
- How is it verified?
- How is it disabled or uninstalled?
- What happens when its state is missing or corrupt?

The theme feature, for example, must provide neutral fallbacks for Starship, tmux,
Neovim, FZF, bat, Delta, btop, and lazygit. Theme-aware wrappers must delegate directly
to the underlying command when the feature is disabled or unresolved.

### Machine state model

Installation state is not “the last tier that was requested.” Three different kinds of
state must remain separate:

1. **Invocation request** — ephemeral input to the current setup run: requested tier,
   tools, feature changes, force/update intent, and dry-run state. A later `--config` run
   does not replace an earlier `--work --ai` request.
2. **Persistent preferences** — explicit machine choices that survive reconciliation,
   such as theme enabled/disabled and agent-badge enabled/disabled. Defaults are applied
   only when a preference has never been recorded. `--no-theme` remains in effect until
   an explicit `--theme`/enable action reverses it.
3. **Component ledger** — the last observed outcome and ownership for every managed
   component: applicable, installed and owned, present but externally owned, skipped,
   failed update with prior version preserved, deliberately removed, or unknown. The
   ledger records enough evidence to verify and safely uninstall what dotfiles owns.

Durable machine state should live under `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/`,
not be inferred from whichever repository command ran most recently. Rendered/rebuildable
artifacts belong under `${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/` or another explicitly
disposable cache. Checkout-local `generated/` files may be read during migration, but
must not remain the sole durable record of machine preferences or ownership.

State update rules:

- Tier and tool requests merge into the component ledger; lower-tier reconciliation does
  not forget higher-tier components.
- Feature preferences change only through an explicit feature enable/disable request.
- A successful install/update records observed ownership and version where available.
- A failed update records the failure while retaining the prior working component record.
- An uninstall records deliberate removal only after owned paths are actually removed.
- Verification reads persistent preferences and the component ledger, then compares them
  with current reality; it never treats the ledger alone as proof that a component works.
- Unknown or externally changed state is reported and reconciled, not silently rewritten.

The state format must be versioned, data-only, atomically replaced, and parseable without
`eval`. The implementation may use TSV, JSON, or another small explicit format, but it
must have schema validation and migration tests.

Atomic replacement protects readers from partial files but does not prevent concurrent
writers from losing each other's updates. Every persistent read-modify-write operation
must therefore acquire an inter-process lock, or use an equivalent compare-and-swap
mechanism, across the complete transaction. This applies to setup, feature switches,
theme commands, migrations, uninstall, and ledger reconciliation. Lock acquisition must
have bounded waiting, actionable diagnostics, and stale-lock recovery that cannot steal a
lock from a live owner.

Artifact installation and ledger recording cannot generally be committed as one
filesystem operation. Dotfiles-owned installers therefore use a small transaction journal:

1. record the intended old/new ownership and staged artifact;
2. validate the staged artifact;
3. replace the owned artifact according to its method-specific contract;
4. verify observed reality;
5. update the component ledger;
6. clear the journal.

On startup, setup/verify detect an incomplete journal and reconcile the ledger from the
observed artifact without repeating a destructive step blindly. Tests must cover two
concurrent writers changing different preferences and interruption after artifact
replacement but before ledger update.

### Shell invocation contract

“Non-interactive shells use Layer 0” describes the desired behavior when dotfiles startup
files are actually read. It does not mean every shell invocation reads them.

| Invocation | Startup contract |
|---|---|
| Login interactive Bash | `.bash_profile -> .bashrc -> .profile`; load Layer 0, Layer 1, then enabled features |
| Non-login interactive Bash | `.bashrc -> .profile`; load Layer 0, Layer 1, then enabled features |
| `bash -lc` | login files are read; refresh Layer 0/project activation, then stop before interactive layers |
| `bash -c` or a Bash shebang | read no dotfiles startup file by default; inherit the parent environment only |
| Login/interactive Zsh | `.zshenv`, then login/interactive files; load Layer 0 once, then Layer 1 and enabled features when interactive |
| `zsh -c` or a Zsh shebang | `.zshenv` is read; refresh Layer 0/project activation, then stop |
| Nested shell after `cd` | Bash refreshes project activation only when launched through a startup-reading form such as `bash -lc`; Zsh refreshes through `.zshenv` |

Layer 0 may use private `_dotfiles_*` helper functions while it is evaluating, but it must
not export public interactive functions or aliases. Helpers should be removed after use
when they are no longer needed. Dotfiles must not blanket-delete functions it does not
own; any external-function sanitization for agent snapshots requires a separate explicit
policy, measured justification, and allow/deny tests.

“No theme initialization” means Layer 0 performs no theme resolution, rendering, cache
write, tmux query, or theme command execution. A child process may still inherit harmless
theme-related environment variables from a themed parent. The core guarantee is that
Layer 0 neither depends on nor refreshes them. A stronger scrubbed environment, if
needed, should be an explicit launcher rather than an accidental side effect of shell
startup.

### Migration contract

Every state or directory-layout change must support existing installations, not only
fresh test homes.

- Machine state and generated-state formats carry a schema version.
- Migrations are ordered, atomic, idempotent, and safe to resume after interruption.
- The old state remains readable until the new state has been validated and committed.
- Global theme selection and overrides are preserved when moving state.
- Existing tmux session/window options are preserved; changed hooks are actively rewired
  or removed in the live server rather than merely disappearing from `tmux.conf`.
- Existing shell processes keep working with old paths until reload or an explicit
  compatibility window ends.
- Compatibility shims have an owner, removal condition, and test; they are not permanent
  alternate architectures.

Expected activation timing must be stated for each migrated surface:

| Surface | Expected activation |
|---|---|
| New shell environment | next shell or `reload` |
| Existing shell theme variables | next prompt/reload according to the feature contract |
| Tmux hooks and status wiring | updated immediately by an explicit sync/unwire operation |
| Existing Neovim process | explicit `:ThemeReload` where supported; otherwise next launch |
| btop/lazygit and similar TUIs | next launch unless the tool supports safe live reload |

Migration acceptance tests must cover an old-format installation, preservation of global
and tmux session/window theme overrides, feature disable/re-enable, live hook removal,
repository relocation, and interruption at each state-write boundary.

### Supported environment and bounded test matrix

Required support is:

- Ubuntu 22.04 LTS, 24.04 LTS, and 26.04 LTS on x86_64;
- Ubuntu 24.04 LTS and 26.04 LTS on aarch64;
- WSL2 on Windows 11 using supported Ubuntu releases;
- WSL2 with systemd enabled as the primary service configuration, with the documented
  shell fallback tested when systemd is unavailable.

Ubuntu 20.04 may retain best-effort compatibility where inexpensive, but it is not part
of the required CI matrix. WSL1 and non-Ubuntu distributions are unsupported.

The required setup matrix is bounded rather than fully combinatorial:

- `config` with theme default and theme disabled;
- `bash` with theme default and theme disabled;
- `dev` and `work` default profiles;
- unit/ownership tests for each individual AI installer plus an `--ai` aggregate dry-run;
- RDP dry-run and installer unit tests, with a periodic/manual live service test;
- native Ubuntu and mocked WSL platform tests, plus a periodic/manual WSL integration run.

Test terminology is defined as follows:

- **Dry-run immutable:** no content, path type, directory entry, symlink target,
  permissions, ownership, or mtime changes under the repository, target HOME, or managed
  system paths. PATH-shim spies also prove that mutating commands such as `mkdir`, `mv`,
  `rm`, `ln`, `cp`, `chmod`, `install`, package managers, `tee`, and `systemctl` were not
  invoked in mutating modes. This catches temporary writes that a final snapshot misses.
- **Idempotent setup:** a second identical successful run creates no backup, rewrites no
  unchanged config or state, changes no managed mtime, performs no unnecessary download
  or package transaction, and leaves the same verification result.
- **Startup regression:** run the base revision and candidate revision with like-for-like
  commands on the same runner in the same benchmark job. Checked-in historical numbers
  are reference/trend data, not the sole comparison baseline. A candidate regression
  larger than both 10 ms and 15% in the median of at least 30 measured runs fails unless
  deliberately reviewed. Keep a separate generous catastrophic ceiling.
- **ARM validated:** report whether the job performed native execution, emulated
  execution, or selection-only testing. Never label selection-only tests as runtime
  validation.

### Execution isolation and parallel-work contract

The deployed dotfiles are live symlink targets. Editing the active checkout can affect
new shells, SSH connections, tmux reloads, Neovim launches, Git behavior, and AI workers
before a commit is complete. Implementation therefore uses an isolated checkout and
isolated machine state by default.

#### Development workspace

- Create a dedicated Git worktree outside `/home/tkeller/dotfiles`; prefer a task-specific
  directory under `/tmp` or another explicitly approved development root.
- Do not repoint live dotfile symlinks at the implementation worktree.
- Keep the active checkout available for unrelated work and for read-only comparison.
- Treat linked worktrees as sharing repository metadata: the common Git directory,
  ordinary repository configuration, and hooks may belong to the active checkout even
  when working files are isolated.
- Development and tests must not install, remove, or rewrite hooks in the shared common
  Git directory, and must preserve shared `.git/config` and related repository settings.
- Do not “fix” linked-worktree hook discovery by redirecting the hook installer to the
  common Git directory during tests; that would make the test mutate the active
  repository more successfully.
- Before integrating, inspect both worktrees for unrelated changes and never reset,
  overwrite, or reformat another task's work.
- Use focused commits so reviewed changes can be integrated without copying an entire
  dirty worktree.

#### Test environment

Tests use dedicated temporary roots for all mutable user state:

```text
HOME
XDG_CONFIG_HOME
XDG_DATA_HOME
XDG_STATE_HOME
XDG_CACHE_HOME
DOTFILES_DIR or test checkout
backup root
temporary bin/PATH shims
tmux socket/server
```

- Tests must not source the real user's shell startup files unless explicitly designated
  as a read-only live-installation diagnostic.
- Bash tests use `--noprofile --norc` or the fixture entrypoints where appropriate.
- Zsh tests override `ZDOTDIR`/HOME so `.zshenv` and `.zshrc` resolve from the fixture.
- Tmux tests always use a unique named server and temporary socket directory; they never
  source configuration into the default server.
- Theme tests override both state and cache roots and may not write the active global,
  session, or window theme state.
- Plugin tests use fixture marketplaces/config directories and do not register plugins
  with the user's real Claude or Codex installation.
- Hook installation/removal tests use a disposable standalone Git repository whose
  `.git` directory, hooks, and configuration are entirely test-owned. Linked worktrees
  may be used for normal source development, but not as the mutation target for hook
  tests.

#### Host-level mutation boundary

Normal development and automated local tests must not invoke live host mutations,
including:

- APT/package repository changes;
- `sudo`, group membership changes, or service enablement;
- Docker daemon installation or configuration;
- xrdp installation or listener changes;
- NVM, Rust, or AI vendor installers against the real HOME;
- real backup retention or uninstall operations;
- writes to the default tmux server.

Use PATH-injected command spies/fakes for unit tests and disposable containers for
integration tests. A real host-level command is reserved for the controlled rollout and
requires explicit authorization at that time.

#### Parallel ownership rules

The following architectural choke points are serialized: only one active workstream owns
each at a time.

- `setup.sh` argument parsing and orchestration;
- `lib/install.sh` and install-result semantics;
- persistent state schema and migrations;
- registry schema/applicability;
- runtime loader boundaries;
- theme state relocation and live tmux migration;
- CI workflow restructuring;
- broad directory moves.

Independent, bounded work may proceed in parallel after its interface is stable, for
example focused shell-helper fixes, Neovim safety fixes, plugin metadata, ARM release
inventory, documentation corrections, and structured-file validators. Every parallel
task must have explicit file/responsibility ownership, preserve unrelated changes, and
avoid broad formatting or generated-file churn.

#### Live integration and rollout

Integration into the active checkout is a separate operation from development:

1. Finish the deliverable and full isolated test suite in the implementation worktree.
2. Review the diff specifically for files that are live symlink targets.
3. Before changing the active checkout, run a read-only preflight with the old code and
   record the current revision, worktree status, config/symlink health, installed component
   versions/ownership, durable state, and live tmux hooks/options.
4. Prepare and validate a scoped recovery procedure: retain state/config backups and know
   how to revert only the integration commits without resetting unrelated work.
5. Prove in an isolated fixture that the candidate code can read the recorded old state
   and operate safely before explicit migration.
6. Present the complete Gate A package and wait for explicit approval.
7. Integrate focused commits into the active checkout without disturbing unrelated work.
   This is already an activation point for newly launched shells and tools, so the
   integrated code must remain backward-compatible with unmigrated state.
8. Immediately run read-only verification against the live installation using the
   integrated code, before migration.
9. Present the complete Gate B package and wait for explicit approval.
10. Apply state/config migration explicitly; do not make a normal shell start perform an
   unbounded or destructive migration.
11. Synchronize/unwire the live tmux server without restarting it or disturbing sessions.
12. Run post-migration verification and test one disposable new Bash and Zsh session.
13. Reload important shells and restart long-running tools only after the disposable
   sessions pass.
14. Record the migration result in the component ledger and retain a recoverable backup
   until the new state has been verified.

Obtain Gate C separately before any host-level or destructive command encountered in
these steps.

Existing shells and AI workers are not forced to reload during development. At rollout,
the expected activation timing follows the migration contract above; workers with a
captured environment may continue on the old environment until intentionally restarted.

#### Mandatory human approval gates

No completion instruction, implementation milestone, passing test suite, or prior approval
to work in the isolated worktree authorizes changes to the live system. The executor must
stop and obtain an explicit user response at each applicable gate below.

**Gate A — live checkout integration**

Required before merging, cherry-picking, copying, or otherwise applying implementation
changes to `/home/tkeller/dotfiles`, because that checkout is the target of live config
symlinks. The approval request must present:

- the exact commits or patch to be integrated;
- the files affected, highlighting live shell, tmux, SSH, Git, and editor targets;
- isolated test results and any untested surfaces;
- the recorded live preflight and current revision;
- expected immediate effects on newly launched shells/tools before migration;
- the scoped rollback procedure and retained backups.

Without explicit approval, work stops with the implementation remaining only in the
isolated worktree.

**Gate B — state/config migration and live-process synchronization**

Required after integration compatibility checks and before writing durable preferences,
migrating state, changing live config targets, modifying the default tmux server, wiring
or unwiring plugins, or reloading important shells. The approval request must present:

- the exact migration and synchronization commands;
- old and new state locations/schema versions;
- what is preserved, rewritten, or removed;
- activation timing for shells, tmux, Neovim, and other running tools;
- interruption recovery and rollback steps;
- the post-migration verification checklist.

Integration approval does not automatically grant migration approval unless the user
explicitly approves both gates together after seeing both complete packages.

**Gate C — host-level or destructive mutation**

Required immediately before any real package-manager operation, `sudo`, service/listener
change, group modification, vendor installer, uninstall, backup rotation, deletion,
credential/plugin registration, or other change outside the already approved live patch
and migration. The request must identify the exact command, target, reason, recovery
limits, and whether the operation can preserve the previous working installation.

Approval is scoped to the presented commands and targets. It does not authorize later
commands merely because they are in the same phase. If the command or target changes, the
executor must ask again unless the user explicitly granted a suitably narrow reusable
approval.

At every gate, silence or an ambiguous response means “not approved.” Read-only preflight,
isolated implementation, and isolated tests may continue, but no live mutation may occur.

## Phase 1 — correctness and safety

Objective: eliminate behavior that can destroy state, silently fail, or contradict the
documented installation path.

### 1.1 Make dry-run immutable

- Do not create `.backups/` or timestamped backup directories during dry-run.
- Do not run backup retention during dry-run.
- Create a backup directory lazily, only before the first real backup.
- Do not initialize or rewrite generated theme/install state during dry-run.
- Audit every installer helper for mutations before its dry-run guard.
- Add snapshot and mutating-command-spy tests for the bounded dry-run matrix defined
  above.

Acceptance criteria:

- `setup.sh --config --dry-run` and `setup.sh --full --dry-run` meet the defined dry-run
  immutability contract.
- Existing backups are never rotated by a dry-run.
- No mutating installer command is invoked and then “cleaned up” afterward.

### 1.2 Remove checkout-path assumptions

- Replace every `$HOME/dotfiles` runtime path with the resolved `DOTFILES_DIR`.
- Make tmux capture `DOTFILES_DIR` once and use it for clipboard, theme, and plugin
  commands.
- Update plugin documentation and metadata to point at real paths.
- Test from the documented default `~/dev/dotfiles` and from a path containing spaces.
- Keep fallback discovery only where a process genuinely cannot inherit `DOTFILES_DIR`.

Acceptance criteria:

- Bootstrap's default location passes the full tmux configuration test.
- No functional source file contains a hard-coded `$HOME/dotfiles` path.
- A custom `DOTFILES_DIR` produces identical behavior.

### 1.3 Correct argument parsing

- Unknown options exit nonzero after showing concise usage.
- Options requiring values validate that a value exists before reading it.
- Multiple tier flags either select the highest tier deterministically or fail with a
  clear conflict; argument order must never downgrade a request.
- `--full` always means `work + all AI tools`, regardless of option order.
- Help and banners list Claude, Codex, opencode, and Pi consistently.
- Remove the unused `wget` prerequisite unless a real consumer is identified.
- Validate requirements for orthogonal flags such as `--ai` and `--rdp`, not only for
  cumulative tiers.
- Confirm the distribution is Ubuntu rather than treating the presence of
  `lsb_release` as proof.

### 1.4 Make requested failures fail

- Preserve the distinction between installed, already present, skipped/not applicable,
  and failed.
- An APT update or install failure must propagate unless explicitly declared advisory.
- Missing eget artifacts must make the requested tier fail.
- A requested AI tool that cannot be installed must make the run partial/failed, not
  “up to date.”
- Print the full summary on failure, then exit nonzero.
- Reserve exit code 2 for a documented top-level partial/not-applicable result if it is
  useful; do not overload it inside individual installers without surfacing the reason.

Acceptance criteria:

- Injected failures in APT, eget, and each installer produce a nonzero setup result.
- Successful re-runs remain zero and idempotent.
- The final success message is printed only when every requested component succeeded or
  was already valid.

### 1.5 Repair immediate correctness defects

- Enable the tracked ripgrep config with `RIPGREP_CONFIG_PATH`, or delete the config if
  its global exclusions are rejected during review.
- Exclude Markdown and other whitespace-sensitive formats from unconditional Neovim
  trailing-whitespace removal; preserve cursor/view/search state.
- Fix `bin/opencode-contract` cleanup so successful commands remain successful.
- Either commit and maintain the opencode contract baseline or remove the baseline
  feature and narrow the command to live inspection.
- Prevent incidental bundled binaries, such as Codex's private `rg`, from being treated
  as durable system-managed installations.

### 1.6 Preserve working installations where dotfiles controls replacement, and make
removal safe

- For dotfiles-owned standalone binaries and extracted trees, never delete or overwrite a
  working installation before its replacement has been downloaded, validated, and staged.
- Replace the current force-reinstall flow that removes eget binaries before fetching
  replacements.
- Download/extract into a temporary staging directory, verify the staged binary, then
  atomically replace the owned path where the filesystem permits.
- If an update fails, keep the previous binary runnable and record the attempted failure
  in the component ledger.
- For APT, vendor installers, self-updaters, and other methods that mutate in place,
  define a method-specific failure contract instead of promising universal rollback. The
  contract states what is expected to remain usable, what may have changed, how observed
  partial state is recorded, and the supported recovery command or procedure.
- Eliminate `eval` from uninstall path expansion.
- Resolve and validate every deletion target against the component's recorded ownership
  and an allowlisted ownership root.
- Reject empty paths, `$HOME` itself, the dotfiles checkout, broad XDG roots, and any path
  outside declared ownership.
- Preserve user configuration, credentials, sessions, and trust databases unless the
  command explicitly names them and obtains confirmation.

Acceptance criteria:

- Injected download, extraction, and verification failures for dotfiles-owned staged
  artifacts leave the previous executable byte-for-byte intact and runnable.
- APT and vendor-installer failure tests verify their documented method-specific partial
  state and recovery contract.
- Interrupted updates can be retried without manual cleanup.
- A malformed registry or ledger entry cannot make uninstall delete outside the owned
  tool path.
- Uninstall reports both removed owned state and intentionally retained user data.

## Phase 2 — operational hardening and test coverage

Objective: build the reusable test infrastructure needed by the safety, state, runtime,
and feature deliverables. Tests for behavior that does not exist yet land with the
deliverable that introduces that behavior; this section is not a gate that must be
completed before later implementation work begins.

### 2.1 Repair current CI gaps

- Add a reusable fixture harness that creates isolated HOME/XDG/PATH/tmux roots and fails
  fast if a test resolves a managed target into the live user environment.
- Add command spies for host-mutating operations and assert expected calls and non-calls.
- Parse `CONFIG_MAP` as `target:type:owner` in the install assertion.
- Assert every applicable symlink and rendered config.
- Stage the test checkout at `~/dev/dotfiles`, matching bootstrap.
- Run setup twice and assert the second run is clean/idempotent.
- Run a dry-run immutability test before and after installation.
- Once profile-aware verification lands, stop treating `bin/verify` as informational in
  the profiles it is expected to verify.
- Pin the ShellCheck action to an immutable commit.
- Pin or deliberately version the install-test container rather than relying on an
  unbounded `ubuntu:latest` transition.

### 2.2 Add shell behavior tests

- Run shared interactive functions in both Bash and Zsh.
- Cover project-directory parsing, PATH deduplication, Docker container arrays, and all
  AI wrapper flag variables.
- Make `tests/agent-shell.sh` hermetic: isolate HOME or emit/parse a unique marker so
  machine-local startup output cannot become arithmetic input.
- Add the agent-shell test to CI after installation.
- Test that non-interactive startup introduces no public interactive aliases/functions,
  leaves no unnecessary dotfiles helpers behind, does not delete externally owned
  functions, and performs no theme initialization.
- Benchmark both fundamental and full interactive startup paths.

Acceptance criteria:

- Every public function in the shared interactive module has at least one Bash and one
  Zsh sourcing/execution smoke test; shell-specific files are tested only in their owning
  shell.
- `bash -lc` and `zsh -lc` load only Layer 0.
- Theme enable/disable does not move Layer 0 beyond the defined 10 ms/15% startup
  regression threshold.

### 2.3 Add focused installer tests

- Test argument parsing without performing installs.
- Test config reconciliation with missing, matching, divergent, and broken symlinks.
- Test backup retention and lazy backup creation in a temporary HOME.
- Test install result aggregation and final exit status.
- Test uninstall path expansion and safety rejection.
- Make the hook installer recognize a linked worktree and refuse to mutate shared hooks
  by default; any shared-hook operation requires an explicit flag and clear target report.
- Test hook installation, checking, force behavior, and removal only in disposable
  standalone repositories.
- Test two concurrent writers updating different persistent preference fields without a
  lost update.
- Interrupt a staged artifact transaction after replacement but before ledger recording,
  then verify deterministic journal recovery.
- Add targeted tests for opencode, Pi, NVM, and Rust ownership behavior comparable to
  the existing Codex installer test.

### 2.4 Validate structured files and integration contracts

- Parse all tracked JSON, JSONC where tooling permits, TOML, YAML, systemd units, and
  EditorConfig in CI.
- Validate that every registry config owner exists.
- Validate that every theme supplies its required files and matching Starship palette.
- Validate plugin generated copies and marketplace manifests.
- Check that every documented executable and option exists and that `--help` exits 0.

## Phase 3 — portable registry and architecture support

Objective: make platform, architecture, installation, verification, updating, and
uninstallation describe the same inventory.

### 3.1 Define registry scope honestly

The registry will cover user-visible managed components, including at least:

- eget tools;
- Neovim, tmux, NVM, Rust;
- Claude, Codex, opencode, Pi;
- Docker and Azure CLI;
- Zsh and other tier-defining APT components where their absence matters;
- WSL-only and RDP components.

Each entry should provide or derive:

```text
name
binary/service verification
install method
minimum tier or feature
platform applicability
architecture applicability
ownership rules
update source
safe uninstall behavior
associated configuration
```

Do not force all data into one encoded string. Prefer separate associative fields or a
simple manifest format with explicit validation.

### 3.2 Make ARM artifact selection explicit

- Inventory every pinned tool's actual x86_64 and aarch64 release assets.
- Prefer eget's native architecture selection after removing x86-only filters.
- Where upstream naming defeats automatic selection, add a small architecture-specific
  override rather than duplicating the entire manifest.
- Gate WSL-only tools on WSL and select their ARM asset when running WSL on ARM.
- Fail before downloading if a requested tool has no artifact for the detected
  architecture.

Testing strategy, in descending order of confidence:

1. Native GitHub-hosted ARM64 runner, when available to this repository.
2. ARM64 container under an ARM runner or QEMU for installer smoke tests that execute
   downloaded binaries.
3. Architecture-injection unit tests that validate selected repository, asset filter,
   target filename, and applicability without executing the artifact.
4. Periodic manual verification on real ARM hardware.

Local x86 tests must not be described as ARM validation. CI should report which ARM
confidence level was exercised. ARM support is unconditional; only the available level
of automated execution coverage depends on runner infrastructure.

### 3.3 Make verification profile-aware

- Implement the versioned persistent-preference and component-ledger model defined above.
- Record current invocation requests separately from durable preferences and component
  outcomes.
- Merge newly observed components into the ledger; never replace the ledger merely
  because a lower tier or `--config` was requested later.
- Preserve failed update attempts alongside the last known working owned installation so
  verification can report both facts.
- Add `verify --installed`, `verify --tier <tier>`, and `verify --all` semantics, or an
  equivalently clear interface.
- A config-only installation must be able to verify successfully.
- Missing Docker, Azure CLI, Zsh, or another requested component must be visible.
- Optional unrequested components should be informational, not warnings masquerading as
  health failures.
- `--no-theme` and other explicit feature preferences remain persistent across ordinary
  setup/config reconciliation until explicitly reversed.

### 3.4 Improve update and uninstall coverage

- Extend update reporting beyond eget where upstream exposes a meaningful version.
- Label self-updating/unpinned tools honestly rather than pretending they are pinned.
- Make uninstall remove only paths owned by this system.
- Separate “print manual instructions” from actual uninstall support in status output.
- Add feature disable/unwire operations for themes and agent-badge without deleting user
  data.

## Phase 4 — shell and daily workflow cleanup

Objective: make interactive helpers predictable, cross-shell, and conservative with user
data.

### 4.1 Establish real Bash/Zsh compatibility

- Replace Bash-only `mapfile` use in shared modules with shell-neutral loops or
  shell-specific adapters.
- Parse colon-separated project roots correctly in both shells.
- Pass lists as arrays rather than relying on Bash scalar splitting.
- Give opencode the same Zsh flag handling as Claude, Codex, and Pi.
- Test `reload` in both shells; feature-toggle tests land with the feature-state
  deliverable.
- Remove or relocate public helpers that duplicate a better core implementation, such as
  the second PATH deduplicator.

### 4.2 Make destructive conveniences conservative

- Change `nclean` to preserve the lockfile and use `npm ci` when appropriate.
- Put lockfile deletion behind a separately named, explicit command.
- Make process helpers send `TERM` by default and require `--force` for `KILL`.
- Confirm destructive Git aliases communicate whether they stage or discard unrelated
  work.
- Keep confirmation prompts for Docker pruning and other broad cleanup.

### 4.3 Repair stale and missing command assumptions

- Replace `netstat` with `ss`, which is present on supported systems.
- Use HTTPS, failure handling, and a timeout for public-IP lookup.
- Use `python3` or `uv run` consistently rather than assuming a `python` shim.
- Remove the unused singular `PROJECTS_DIR`.
- Remove the nonexistent `TMUX_PREFIX` customization claim or implement it properly.
- Review the archive extractor for modern formats such as `.tar.xz` and `.tar.zst`.
- Ensure shortcuts are only advertised when the underlying behavior exists.

### 4.4 Reduce startup and sourcing ambiguity

- Keep Layer 0 free of theme and plugin code.
- Re-evaluate whether `direnv export` should run for every non-interactive Zsh process,
  documenting the Bash/Zsh asymmetry if retained.
- Keep machine-local files from making repository tests non-hermetic.
- Ensure missing optional tools do not install wrappers that fail with unrelated theme
  errors before reporting the missing tool.

## Phase 5 — configuration ownership and subsystem boundaries

Objective: make configuration composition obvious and prevent optional features from
owning core files.

### 5.1 Isolate the default theme feature

- Introduce a single feature-enabled check used by setup, shell startup, wrappers,
  verification, and tmux.
- Move theme resolution and rendering behind the feature boundary after tests cover the
  existing behavior.
- Migrate durable theme selection/preferences into XDG state and rebuildable artifacts
  into the feature cache, using the versioned migration contract above.
- Provide neutral, static fallbacks when the feature is disabled:
  - Starship uses a valid base palette/config.
  - Tmux uses readable default styles and no theme hooks.
  - Neovim loads a safe fallback colorscheme.
  - FZF, bat, and Delta use their native defaults.
  - btop and lazygit wrappers delegate directly.
- Preserve the existing twelve-theme catalog unless a theme fails quality checks or is
  intentionally retired.
- Continue running contrast and full theme-cycle tests when the feature is enabled.
- Add an explicit live-server sync/unwire operation so disabling the feature removes old
  tmux hooks and status options from already running servers.

Acceptance criteria:

- Default installs look and behave as they do today, aside from deliberate fixes.
- `--no-theme` requires no generated theme files and all core tools remain usable.
- Non-interactive/AI shells never invoke the theme switcher.
- Corrupt or missing theme state falls back cleanly instead of blocking shell startup.
- Upgrading an existing installation preserves global, session, window, group, and tool
  overrides through the migration.
- Disabling and re-enabling themes is persistent, reversible, and does not leave stale
  live tmux hooks.

### 5.2 Make agent-badge independently optional

- Remove direct shared-plugin wiring from the base tmux config.
- Let the installed Claude/Codex plugin wire and reconcile itself.
- Add an explicit `--no-agent-badge` escape for AI installs if useful.
- Correct marketplace paths, homepage URLs, warning messages, and documentation.
- Retain `plugins/shared/` as the source of truth while marketplace packages must be
  self-contained.
- Ensure install, trust/review, disable, and uninstall instructions are complete.

Acceptance criteria:

- Tmux behaves normally with no AI CLI or plugin installed.
- Installing either supported marketplace package adds badges without editing core tmux
  configuration.
- Removing the plugin removes its hooks and format fragments cleanly.

### 5.3 Simplify Git configuration ownership

- Split portable Git behavior from machine identity.
- Prefer an include-based tracked base config over repeatedly rendering the full global
  config.
- Preserve an existing user config and identity without timestamp backups on every
  reconciliation.
- Keep `~/.gitconfig.local` as the final machine-local override.
- Ensure Delta's optional theme include disappears cleanly when themes are disabled.

### 5.4 Repair and pin the current Neovim configuration

Neovim modernization is a separate optional project and is not required for this
improvement program. This plan keeps the current Vimscript approach while making it safe
and reproducible:

- do not download the plugin manager implicitly during ordinary editor startup;
- pin or lock plugin revisions using the current ecosystem where practical;
- keep theme integration behind the theme feature adapter;
- preserve the established keymap unless a mapping is intentionally retired;
- fix whitespace-sensitive file handling and other confirmed defects;
- add headless startup and representative editing tests.

A later Lua/LSP/Tree-sitter migration should have its own proposal, compatibility goals,
and rollback plan rather than riding along with installer/runtime safety work.

## Phase 6 — supply-chain and uninstall hardening

Objective: make trust decisions explicit and apply strong verification where upstream
supports it.

### 6.1 Binary and source downloads

- Build on Phase 1's staging and working-install preservation; this phase strengthens
  artifact authenticity rather than introducing the basic safety property.
- Verify published checksums or signatures for eget, Neovim, tmux, and other pinned
  release artifacts when upstream provides stable verification material.
- Download with `--fail`, HTTPS-only/TLS restrictions, bounded timeouts, and temporary
  files.
- Verify archive structure before replacing an existing installation.
- Validate Docker and Microsoft repository key fingerprints before trusting them where a
  stable published fingerprint exists.

### 6.2 Moving official installers

Claude, Codex, opencode, NVM, and rustup do not all offer equivalent pinning or checksum
contracts. For each one, document whether it is:

- version-pinned and checksum-verified;
- version-pinned but HTTPS-trusted;
- intentionally moving/self-updating and HTTPS-trusted.

Download scripts to a file before execution, reject empty/unexpected responses, never run
them with sudo, suppress shell-rc modification, and verify owned outputs afterward. Do not
add fake checksum theater when no trustworthy upstream checksum exists.

### 6.3 Audit ownership and native uninstallers

- Review the Phase 1 path-safety implementation against the completed component ledger.
- Prefer tool-native uninstallers where they accurately preserve user data and can be
  constrained to recorded ownership.
- Add adversarial tests for malformed state, symlink escapes, spaces/newlines in paths,
  and interrupted removal.
- Report retained configuration/session data after uninstall.

## Phase 7 — documentation, metadata, and forgotten components

Objective: leave one accurate mental model and remove abandoned promises.

### 7.1 Consolidate documentation

- Keep README focused on installation, daily use, and links.
- Make one architecture document authoritative for tiers, runtime layers, features, and
  ownership.
- Keep focused theme, AI-egress, customization, and remote-desktop documents only where
  they add operational detail.
- Remove duplicated diagrams and theme/tool counts that must be manually synchronized.
- Generate inventory tables from the registry where practical.
- Move implemented/resolved issue specs into an ADR/archive section; keep only active
  proposals under `issues/`.

### 7.2 Resolve forgotten assets

- Decide whether `.claude/skills/shell-expert` is a shipped feature:
  - if yes, update it to this repository's actual tools and install/document it;
  - if no, remove it from the repository.
- Commit and maintain the opencode contract baseline, or remove the baseline workflow.
- Remove dead variables, stale comments, invalid paths, and obsolete commands.
- Remove the executable bit from non-executable configuration files.
- Add font guidance or disable Powerline-font assumptions in Neovim.

### 7.3 Licensing and third-party material

- Choose a repository license before treating the marketplaces as generally reusable.
- Add third-party notices for vendored tmTheme files and other copied palette assets.
- Record source URL, upstream license, and local modifications for vendored material.

The repository owner must choose the license; implementation should not silently impose
one.

## Implementation sequence and commit discipline

The numbered phases are thematic tracks, not strict stage gates. Implementation follows
explicit dependencies, and each deliverable must land with the tests needed to prove its
own acceptance criteria. Do not add a failing test for a future feature and then leave the
branch red until a later “phase.”

Dependency graph:

```text
Isolated worktree + HOME/XDG/PATH/tmux fixture harness
  -> every implementation deliverable

Safety test harness
  -> dry-run fix
  -> failure propagation
  -> staged update safety

State schema + migration harness
  -> persistent feature preferences
  -> minimal component ownership records
      -> ownership-constrained uninstall
      -> full component outcome ledger
          -> profile-aware verification

Shell invocation contract tests
  -> Layer 0/Layer 1 loader boundary
  -> Bash/Zsh compatibility fixes
  -> startup regression gates

State schema + theme fallback contract
  -> persistent theme enable/disable switch
      -> old-state compatibility migration
      -> live tmux sync/unwire
      -> one deployment unit: switch + migration + live cleanup

Registry applicability model
  -> platform gating
  -> ARM asset selection
  -> update/uninstall inventory coverage
```

Until minimal ownership records exist, uninstall must refuse any removal whose ownership
cannot be established from current explicit configuration. It must not use broad inferred
paths as an interim shortcut. Persistent feature switching must not deploy before its
state schema, old-state compatibility reader, migration, and live unwire path are all
ready, even if those pieces are developed in separate commits.

Within those dependencies, the preferred commit discipline is:

1. Add or repair the failing test that demonstrates a defect.
2. Make the smallest behavior change that satisfies the invariant.
3. Run the focused test plus the complete local suite.
4. Update the authoritative documentation in the same commit.
5. Avoid mixing directory moves with behavioral changes unless separation is the behavior
   under test.

Recommended early commit groups:

```text
test(harness): isolate HOME, XDG state, PATH mutations, and tmux servers
test(install): expose dry-run mutation and CONFIG_MAP assertion gap
fix(install): make dry-run immutable and propagate requested failures
fix(paths): honor DOTFILES_DIR throughout tmux and plugin integration
feat(state): add versioned preferences and minimal ownership records
fix(install): stage replacements and constrain uninstall ownership
feat(state): record component outcomes and recover interrupted transactions
feat(verify): reconcile recorded intent with observed component health
test(shell): add Bash/Zsh shared-function matrix
fix(shell): remove Bash-only behavior from shared modules
fix(config): activate ripgrep config and preserve Markdown whitespace
fix(opencode): repair contract exit semantics and choose baseline policy
refactor(runtime): establish core, interactive, and feature loaders
feat(theme): make the default theme feature independently disableable
feat(migrate): preserve theme state and rewire live tmux servers
refactor(registry): add platform, architecture, and requested-state metadata
test(arm): validate aarch64 artifact selection
```

## Definition of done

The program is complete when all of the following are true:

- Routine development and automated local tests run outside the live checkout and do not
  mutate the real HOME, default tmux server, package database, services, or user groups.
- Linked-worktree development and tests do not mutate the active repository's shared
  hooks or Git configuration; hook tests use disposable standalone repositories.
- The documented bootstrap command works from `~/dev/dotfiles` without hidden path
  assumptions.
- Every dry-run is filesystem-immutable.
- Every requested installation failure produces a nonzero result.
- Failed updates of dotfiles-owned staged artifacts leave the prior installation
  runnable; package-manager and vendor-installer failures follow an explicit,
  tested method-specific recovery contract.
- A second identical setup run is idempotent.
- A later lower-tier reconciliation does not erase higher-tier component history or
  persistent feature preferences.
- Persistent state is versioned, data-only, atomic, and recoverable after interruption.
- Concurrent persistent-state writers cannot lose independent updates, and an interrupted
  artifact/ledger transaction is detected and reconciled deterministically.
- Config-only, bash, dev, work, AI, and RDP selections can each be verified according to
  what was requested.
- Bash and Zsh shared commands pass behavioral tests.
- Startup-reading non-interactive and AI worker shells execute only Layer 0, with no
  theme/plugin initialization; `bash -c` and Bash shebangs continue to inherit their
  parent environment without implicitly reading dotfiles startup files.
- Themes are enabled by default but can be disabled without breaking core tools.
- Existing theme state migrates without losing global/session/window overrides, and live
  tmux hooks are explicitly synchronized or removed.
- Agent-badge can be installed and removed without editing or breaking base tmux behavior.
- x86_64 and aarch64 artifact selection is explicit and tested; native ARM execution is
  used where CI infrastructure permits.
- Update and uninstall operations report ownership and never silently delete broad paths.
- The main documentation contains no known stale tier, path, theme-count, or command
  claims.
- The full CI suite is required rather than informational for supported profiles.
- The repository is clean after all tests, including failure-path and dry-run tests.
- The final live rollout records health and recovery state before integration, verifies
  backward compatibility before migration, and has a documented migration result, tmux
  synchronization step, disposable-shell smoke test, and recovery path.
- Live checkout integration, state migration/live-process synchronization, and
  host-level/destructive mutations each stop at their mandatory human gate and proceed
  only after an explicit approval covering the presented commands and targets.

## Open decisions to resolve during implementation

These do not block Phase 1:

- Whether multiple tier flags select the maximum tier or are rejected as conflicting.
- Whether the feature-disable flags are named `--no-theme` / `--no-agent-badge` or are
  exposed through a general `--without <feature>` interface. Prefer the simpler interface
  unless more than a few features need it.
- Whether opencode contract snapshots justify their maintenance cost.
- Which license the repository and published plugins should use.
- Whether a native hosted ARM runner is available; if not, which QEMU/manual cadence is
  acceptable.
