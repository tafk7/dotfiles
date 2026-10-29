# Install, update, and refresh: review and redesign

Status: implemented, on `main` since 2026-10-27; what was built and where it
departs from this proposal is in [the status](setup-update-status.md). This is
the proposal as written, revision 2, which takes in
[the review](setup-update-redesign-review.md): it corrects findings the review
showed to be wrong or overstated, and replaces the contracts it showed to be
underspecified. File references are to `352b71e`. Claims marked *observed* were
seen on the author's machine on 2026-10-25 rather than derived from code.

## Summary

Setup is good at a first install and at keeping eget tools on their pins. It
has no record of a machine's intended selection, no update command, a dry-run
that previews attempts rather than changes, and no way to tell or fix what
running processes have not picked up. The sharpest case: the exported shell
load guards are inherited through the tmux server, so new panes skip the
environment code and repo changes to PATH, EDITOR, or LESS do not reach them.

The proposal keeps the engine (registry, ledger, eget lock, journal, setup log,
test harness) and builds on it in this order:

1. **Observation before action.** A structured, side-effect-free observation
   per component, and three separate outcome classes: convergence, health, and
   advisory.
2. **A machine profile** with defined merge, opt-out, and migration rules.
3. **One version authority** (`versions.lock`) that models artifacts, not
   version strings.
4. **Config state** that records exactly what was deployed, so retirement is
   safe.
5. **Refresh** with a bounded environment producer, scoped tmux handling, and
   persistent staleness tracking.
6. A `dotfiles` **front door**: `update`, `verify`, `apply`, `refresh`, `bump`,
   `profile`. A thin `update` with stated limits comes early; the full one comes
   when the contracts above exist.

## What works and should stay

- The registry (`lib/registry.sh`) drives presence checks, the ledger, verify,
  and uninstall, and distinguishes command presence, runnable launchers, files,
  companions, and services (`:274-294`).
- Ownership in the ledger, and per-component replacement rules: setup does not
  replace a tool it did not install unless `--force`, and Codex and OpenCode
  refuse external installs even then (`installers/install-codex.sh:103-111`,
  `installers/install-opencode.sh:20-25`).
- The artifact journal (`lib/state.sh:218-306`): a pending transaction blocks
  further replacements until it is reconciled. That is a recovery contract, not
  a defect (`tests/transaction-failures.sh`).
- eget pins are hash-locked, staged under a fake HOME, verified, and swapped
  atomically. Re-runs skip on a recorded pin and binary hash.
- Configs are symlinks into the checkout, so most edits reach new processes
  with no deploy step. The symlink engine backs up displaced files.
- Every setup run is logged with a ledger diff (`lib/setup-log.sh`).
- The no-sudo base tiers, and the test harness's isolated HOME.

## Findings

### 1. No record of intended selection

Tier and capability flags are not stored. Stored machine state covers feature
preferences (`lib/state.sh:138-170`) and WSL details (`lib/install.sh:417-419`).
`verify --installed` works from the ledger, but the ledger records outcomes,
including discovered external tools and not-applicable components that were
never selected (`lib/install.sh:120-135`), so it cannot stand in for intent.
Re-applying the machine's selection means retyping it.

### 2. Shell load guards are inherited through tmux

`_DOTFILES_BASE_ENV` (`entry/profile.sh:57`) and `_DOTFILES_ENV_LOADED`
(`shell/env.sh:11`) are exported. A tmux server started from a dotfiles shell
holds both in its global environment (*observed*), and every new pane inherits
them, skipping the locale/XDG/PAGER/LESS block and all of `env.sh`. `<prefix> r`
does not touch the server environment. `docs/maintenance.md:5-6` promises
edits reach "the next shell"; checkout discovery itself still works, because
the entry files set `DOTFILES_DIR` before the guards
(`docs/architecture.md:39-41` holds).

- `reload` (`shell/tools/general.sh:135`) clears `_DOTFILES_ENV_LOADED` and
  `_PROFILE_LOADED` but not `_DOTFILES_BASE_ENV`, and under zsh does not re-run
  the profile. Removed aliases and functions persist (documented there).
- `${VAR:-default}` exports keep inherited values even with guards cleared, so
  clearing guards alone does not pick up changed defaults or drop stale PATH
  segments.
- tmux session environments override the global one, and `update-environment`
  re-imports listed variables on attach, so a global fix is not a complete one.

### 3. No update path; pin behavior differs by component

Making a machine current takes many manual, mostly undocumented steps: pull,
setup with the remembered flags, apt upgrades, per-CLI updates, rustup, nvm,
editor plugins, plugin updates, verify.

| On rerun with a moved pin | Components |
|---|---|
| Converges, when dotfiles owns the install | eget tools, neovim, tmux, eget |
| Keeps the old version; sbx warns, nvm does not compare at all | sbx (`installers/install-sbx.sh:26-33`), nvm (`install-nvm.sh:33-41`) |
| Never moves an existing install | vim-plug (`bin/install-editor-plugins:18`), Neovim plugins (`PlugInstall` only); editor plugins are a separate opt-in action no setup phase calls |
| Unpinned | docker and other apt packages, rust, claude, codex, opencode, pi, aws-cli, Node/npm (nvm installs latest LTS and `npm@latest`, `install-nvm.sh:83-102`) |

Pins live in `eget.toml` + `eget.lock`, `lib/config.sh` (neovim, tmux, sbx),
`installers/install-eget.sh:12`, `installers/install-nvm.sh:49,55`, and
`bin/install-editor-plugins:19` / `configs/init.vim`. `check-updates` compares
only eget pins in its JSON and exit code (non-eget lookup failures do affect
the text-mode exit). Work verification warns on an sbx pin mismatch
(`lib/work-host.sh:139-146`); nothing else compares installed identity with the
pin. Two bootstrap downloads are pinned by version but not by digest: eget
(`installers/install-eget.sh:42-49`) and nvm (`install-nvm.sh:49-64`).

### 4. Dry-run previews attempts, not changes

The preview stops before the eget pin/hash decision (`lib/install.sh:919`),
lists every apt package rather than missing ones (`:650`), keeps a second copy
of the config loop (`setup.sh:492` vs `:520`), and never forwards `--dry-run`
to installers that accept it (`lib/install.sh:838-841`). On an up-to-date
machine it reports nearly every component as an action (*observed*). It also
writes and rotates setup logs (`lib/setup-log.sh:48-61`); that is intended,
and should be stated as the one write a preview makes.

### 5. `--force` couples two unrelated intents

`--force` sets `FORCE_OVERWRITE` and `FORCE_REINSTALL` together
(`setup.sh:145-147`), so there is no way to reinstall one tool, or move one tool
to its pin, without also forcing config overwrites. Its reach is narrower than
"everything": `install_apt` ignores it (`lib/install.sh:645-676`), already-current
links are left alone (`:497-500`), and Codex/OpenCode still refuse external
installs.

### 6. The registry drives only part of the install

Installers per tier are hard-coded (`lib/install.sh:1157`, `:1400-1419`), as are
capabilities (`setup.sh:25-32`), the AI flags (`:124`), the help text, and the
apt groups (`lib/config.sh:82-90`, which have no component rows). The unused
`component_selected` (`setup.sh:224-229`) is not a usable replacement: for
`--claude` it selects every AI tool (`tests/fixtures/setup-selection.snapshot`),
while installation honors `SELECTED_AI_TOOLS` (`:233-240`). The registry also
discards table order when parsed (`lib/registry.sh:172-259`), and table order
was never a dependency order (eget appears after tools that need it).

### 7. Config deployment has no retirement

- Removing a `CONFIG_MAP` entry leaves its link in place. The `config.*` ledger
  rows are written on every successful pass, current or not (`setup.sh:537-538`),
  and nothing reads them, so they do not prove setup created a link.
- AI settings are merged recursively; objects merge, scalars and lists are
  overwritten (`lib/config_files.py:33-42`), but nothing is ever removed, so a
  key dropped from the overlay stays in the target.
- The gitconfig re-renders on any run that reaches config reconciliation;
  `diff-config` and `verify` check that the rendered file and include exist, not
  that the content is current (`bin/diff-config:100-107`, `bin/verify:123-132`).
- pbcopy/pbpaste and the wsl2-ssh-agent unit have no ledger coverage. xrdp's
  `/etc` edits are backed up by its installer; hooks are ownership-checked links.

### 8. Ledger accuracy

- An apt tool skipped because it is present loses `package-manager` ownership
  (`lib/install.sh:63-85`). zsh is hard-coded `ok` (`:1152`), so the summary
  reports it installed on every run.
- Versions are probed as the first line of `--version` after resolving the path
  (`:50-52`, `:77`), which records a snap shim for gcloud and keeps ANSI codes
  and banner lines (*observed*: gcloud at `/usr/bin/snap`, btop with escapes).
- `bin/ai-update` execs an installer directly: no setup log, no ledger update.

### 9. Robustness

- Phases run as `fn || FAILED=true` (`setup.sh:635-641`), which disables errexit
  inside them; some failures pass unchecked (`lib/install.sh:394`, `:740`, `:743`).
- A failed replacement leaves its journal pending, by design, and every later
  replacement in the run then fails (`lib/state.sh:234-236`). The defect is that
  setup makes no bounded attempt to reconcile before giving up on the rest.
- `--work` runs `sudo systemctl enable --now docker` on every run
  (`lib/install.sh:1338`).
- The eget fallback "current" test is a substring match on `--version`
  (`:1003`); the recorded binary hash is what actually prevents re-downloads.
- `configs/init.vim:27` configures `fzf#install()`. Whether it fetches an
  unverified binary when the eget fzf is on PATH is unconfirmed; check the
  pinned plugin's installer before acting.

## Design

### Outcomes

Every check produces one of four classes, and commands exit on them
consistently:

| Class | Meaning | Examples | Exit |
|---|---|---|---|
| convergence | apply has work to do, or failed to do it | missing selected component, owned component off its pin, stale deployed config | 1 |
| health | apply cannot fix it; needs you | Tailscale not enrolled, KVM unusable, group membership pending, foreign install shadowing an owned one, stale processes | 2 |
| incomplete | a check could not be made | unreadable state, timeout, applicability unknown, observation exit 3 | 3 |
| advisory | informational | newer upstream releases, checkout behind upstream, foreign install satisfying a selection | 0 |

"Converged" means every observation completed and none produced a convergence
finding; it is exactly what `apply` drives to. "Healthy" is separate. All
findings are always printed; the exit code is the first that applies, per
command:

| Command | Exit precedence |
|---|---|
| `verify` | convergence 1, incomplete 3, health 2, else 0 |
| `apply`, `update`, `profile` changes | convergence 1, incomplete 3, else 0 (health is reported, not an exit status) |
| `refresh` | incomplete 3, else 0 (stale processes are reported) | Checkers
emit records (class, section, subject, message), so no command parses another
command's display text or trusts a wrapper's exit status. `verify --smoke`,
which creates a sandbox, stays a separate mutating mode.

### Component observation

Each component exposes an observation with no side effects, printed as
`key=value` lines on stdout (diagnostics on stderr):

    applicable=yes|no|unknown   reason=...
    path=/resolved/path         owner=dotfiles|package-manager|external|none
    identity=<kind>:<value>     want=<kind>:<value>
    runnable=yes|no             companions=ok|missing:<list>
    ready=yes|no                ready-reason=...

Exit 0 means the observation is complete; exit 3 means it could not be made
(command failed, state unreadable, timeout), which is distinct from any result.
The engine, not the installer, turns an observation into a decision (install,
converge, configure, leave, report), so ownership drift and version drift can
both apply at once, and downgrades are just "identity ≠ want".

- Installers gain `--observe`, which must branch before any provisioning (the
  Claude, Codex, and Pi installers configure things before reporting "already
  installed" today). eget tools and apt packages are observed by the engine.
- Version probes follow a per-component rule in the registry: some must not be
  executed (`observed_component_version` already avoids running Azure CLI,
  `lib/install.sh:101-115`). Login shells are never launched by an observation.
- A foreign install that satisfies a selection is an advisory, not a failure:
  apply deliberately leaves it, so verify must not fail on it forever.

**Dry-run** becomes: observe, project the plan's effects on dependent steps
(configs whose owner the plan installs, gitconfig sections that depend on
delta or nvim), print the plan, and mark what cannot be known in advance as
`unknown`. Apply re-observes immediately before each mutation. The plan is not
claimed to be exact where it depends on downloads or package indexes.

### Selection and dependencies

The registry keeps an explicit ordered list and gains a `needs` column (eget
before eget tools; apt build dependencies before tmux; packages before xrdp
configuration; docker before sbx; Node before Pi). Selection is computed from
tier, capabilities, and the per-tool AI list, never from `component_selected`
as it stands. `--only X` installs `X` and reports unmet `needs` as blockers
rather than installing them; Pi alone still does not pull in the work
toolchain (`installers/install-pi.sh:55-72`).

Bundles skip what does not apply; explicit requests fail. `--work` installs the
work tools the platform supports: where sbx is not applicable (WSL, Ubuntu
22.04, unsupported architecture) it records sbx as not-applicable, skips the
KVM and builder steps (`lib/install.sh:1406-1409`), and verify skips the sbx
and KVM checks. Verify's combined work-host checker (`bin/verify:277-289`,
`lib/work-host.sh:128-175`) is split so Docker readiness (local endpoint,
service, group membership) is still checked wherever Docker is selected. A
native host where sbx applies but KVM is unusable keeps today's behavior
(install, warn; verify reports health). Explicit requests still fail when not
applicable, for example `--azure` on Ubuntu 26.04, which this repository's
registry excludes (`lib/registry.sh`, azure-cli row).

### Machine profile

`~/.local/state/dotfiles/profile` (TSV, schema-versioned, written atomically
under the operation lock) records intent:

- `tier`; capabilities; the AI tools by name, or `ai=all` plus an `ai.exclude`
  list. `all` follows the registry (a newly added AI tool appears in the next
  plan as an addition, so it is visible before it installs); `--remove pi`
  under `ai=all` records `ai.exclude=pi` rather than converting to a list;
- durable opt-outs: `--no-git`, `--no-hooks`; `xrdp.session`;
- `editor-plugins=yes|no` (opt-in, as today).

Feature toggles stay in `preferences.tsv` and `dotfiles-feature`; the profile
does not duplicate them.

The profile records what the machine should have. Changing it changes what
is managed, never what is removed.

Every change follows the same order, whether it comes from `dotfiles profile`
or from setup flags: **validate, save, plan, apply.**

1. Validate: unsupported explicit requests (`--azure` on Ubuntu 26.04) are
   rejected before anything is saved.
2. Save the new intent.
3. Show the plan; interactive runs confirm before applying.
4. Apply. If apply fails, the profile keeps the new intent and verify reports
   what is missing as a convergence failure until an apply succeeds.

```
$ dotfiles profile
tier          work
capabilities  ai (all), tail
opt-outs      none

$ dotfiles profile --add rdp
profile: + rdp
plan:    install xrdp, xfce4 session; enable xrdp.service (needs sudo)
apply now? [Y/n]
```

| Change | Command | Effect |
|---|---|---|
| Add a capability or AI tool | `dotfiles profile --add rdp` | Saved, then installed. |
| Raise the tier | `dotfiles profile --tier work` | Saved, then the tier's tools install. |
| Remove a selection | `dotfiles profile --remove pi` | Saved; pi stays installed but is no longer managed (update leaves it, verify stops expecting it). The plan prints the `uninstall-tool` command for anyone who wants it gone. |
| Lower the tier | `dotfiles profile --tier dev` | Same: the work tools stay, unmanaged, with uninstall commands listed. |
| Opt out of a step | `dotfiles profile --add no-hooks` | Remembered by every later apply and update. |

- **Invocation scope is not intent.** A setup run does what its flags say, as
  today, and merges those flags into the profile; it never applies the rest of
  the profile. `setup.sh --config` stays config-only (no packages, no sudo)
  even on a machine whose profile says `work`. Only `dotfiles apply`,
  `update`, and `profile` changes apply the whole profile.
- Setup flags **merge**: a higher tier raises the profile, capability and AI
  flags add, opt-outs set. They never lower or remove. `setup.sh --claude`
  after a full install adds nothing; `--config` adds nothing. Lowering and
  removing go through `dotfiles profile`.
- `--dry-run` never writes the profile; the preview's only write is its log.
- Removal never uninstalls, and never retires configs. A combined
  `--remove X --uninstall` can come later if the two are always used together.
- Migration: with no profile, `dotfiles profile --propose` derives one from the
  ledger (dotfiles-owned and package-manager rows only) and prints it for
  confirmation. It is never adopted silently.

### Versions and artifacts

`versions.lock` becomes the single authority; `eget.toml` tags are generated
from it (or validated against it) so there are no competing sources. Rows are
per component, per platform, keyed with normalized architectures (`x86_64`,
`aarch64`; `amd64`/`arm64` are mapped on read). Each row says what is wanted
and how to recognize it installed:

| Component kind | `want` | Installed identity | Download trust |
|---|---|---|---|
| eget tools | release tag | extracted binary sha256, per architecture, recorded in the lock by `bump` when it writes the row | archive sha256 |
| neovim, tmux | release tag | per-tool version parser; tmux, built locally, by version only | source/archive sha256 |
| eget, nvm bootstrap | release tag | version parser | **add** a sha256 (closes the gap in finding 3) |
| Node | exact version (an LTS release) and its bundled npm version | nvm's default alias, and `npm --version` from that Node's own path; an independently upgraded npm is drift | nodejs.org's signed `SHASUMS256.txt` |
| Rust toolchain | exact toolchain (e.g. `1.92.0`) | `rustup default`, run from a neutral directory with `RUSTUP_TOOLCHAIN` unset and `RUSTUP_AUTO_INSTALL=0`, so project overrides cannot answer and nothing is installed | rustup's channel-manifest verification |
| sbx | exact apt package version, held | `dpkg-query` version, and the hold | apt signature |
| aws-cli | exact version | `aws --version` | versioned zip plus the existing signature check |
| vim-plug | commit | sha256 of the downloaded `plug.vim` (it is a single file, not a checkout) | commit-pinned URL plus that sha256 |
| Neovim plugins | commit | `git rev-parse` of each plugin checkout | commit pin |

A tag and a reported version are different things (sd 1.1.0 reports 1.0.0), so
"installed = pin" always compares identities of the same kind. Missing,
duplicate, or malformed rows are errors. The parser is bash/awk, because the
bash tier does not require Python. The eget installed identity is compared
with the lock's extracted-binary digest, not with the hash the ledger happened
to record locally.

**What gets pinned.** Everything dotfiles downloads itself is pinned; packages
are left to their package manager:

| Pinned (`converge`) | Not pinned |
|---|---|
| eget tools, eget, neovim, tmux, nvm, Node, the Rust toolchain, aws-cli, vim-plug, Neovim plugins; sbx (exception below) | apt-repo tools (docker, tailscale, gcloud, azure-cli): pinning would fight `apt upgrade`, need holds, and delay their security fixes. Distro packages (git, zsh, build tools): Ubuntu keeps only the current version. AI CLIs and Pi, rustup itself: vendor-updated. |

Unpinned tools are still reviewed monthly (see Maintenance); they just are not
gated by the lock.

**sbx is the one pinned apt package.** Kits and controllers built on it need
an exact version (`lib/config.sh:10-12`; the kits are validated against it,
`kits/README.md`), so it stays pinned and held despite moving quickly. When
setup places the hold it writes a receipt to
`~/.local/state/dotfiles/holds.tsv`, and it only ever moves holds it has a
receipt for; any other hold is a health finding, never overridden. This
machine's existing hold predates receipts and cannot be told apart from an
administrator's, so the first run under the new code asks once whether to
adopt it.

### Policy, ownership, and configuration are separate

The registry gains three independent columns:

- `policy`: `converge` (owned installs move to the pin), `present` (ensure
  installed; versions come from the package manager: docker, tailscale,
  gcloud, azure-cli, xrdp, zsh), or `vendor` (ensure installed; the vendor
  updater owns versions: claude, codex, opencode, pi, rustup itself).
- `backend`: eget, apt, installer, source build. Already implied by `method`.
- `configure`: the configuration steps for the component (AI settings, badge
  registration, service enablement), extracted from the installers so they run
  and are checked whether or not the binary needed work, including for
  intentionally external CLIs. Rewiring the tmux badge is not the same as
  updating Claude's plugin cache; plugin update is its own step.

Ownership rules do not change: foreign installs are never adopted or upgraded
implicitly, and per-component force rules stay as they are. `--force` splits
into `--reinstall[=X,...]` and `--overwrite-configs`; `--force` stays as both.

### Config state and retirement

After each deployed entry succeeds, apply records it in
`~/.local/state/dotfiles/deployed.tsv`: target, kind (link, rendered file,
merged file, hook), the exact link target or content digest, and the run id.
Entries update one at a time, so a partial failure keeps earlier entries and
never records writes that did not happen.

An entry is retired only when its source left the manifest (not when a
selection was removed, an owner is unavailable, or `--only`/`--no-git` skipped
it), and only if the target still matches the recorded identity exactly: the
same link target string, or the same content digest. Links are unlinked, never
traversed. Targets must sit under the approved roots, honoring custom XDG roots
(`lib/install.sh:457-485`). Retirements are backed up and reported. Historical
`config.*` ledger rows do not authorize retirement.

AI settings retirement is a three-way comparison per leaf path: last applied
overlay, current target, new overlay. A leaf that left the overlay is removed
if the target still holds the value dotfiles wrote; an edited one is kept and
reported once as a conflict, and the record remembers that. Active overlay
keys keep winning, as today. Lists are leaves; containers left empty by a
removal are removed. Pi's seed-once settings stay user-owned.

### Apply, refresh, update

Each layer contains the next, and refresh runs exactly once, at the end of
whichever command was given:

| Command | Changes | Analogy |
|---|---|---|
| `refresh` | Running processes only: the tmux server's environment and config, badge wiring, theme. Reports stale shells and programs. Never writes outside state. | `systemctl reload` |
| `apply` | Disk, in two phases: components, then configs (links, the rendered gitconfig, AI settings, hooks, caches). Then refresh (`--no-refresh` skips it). | `make install` |
| `update` | Pull, then apply, with `--upgrade` work between apply's two phases. | `git pull && make install` |

Use `update` to take upstream changes, `apply` after editing the live checkout
or changing the profile, and `refresh` when something running is stale while
the disk is right (for example, panes started with an old environment).

Apply's config phase runs after every binary change, because some configs
depend on installed versions (the gitconfig's conflict style needs Git 2.35,
`lib/install.sh:588-599`): link configs, re-render the gitconfig, run
`ai-config` (with the retirement above), install hooks, and drop caches whose
inputs changed.

### Operation lock

Every command that changes state takes one exclusive operation lock for its
whole run: `setup.sh`, `dotfiles update`, `apply`, `refresh`, `profile`
changes, `uninstall-tool`, `ai-config` when it writes, and `verify --smoke`
(it creates a sandbox).

- Only the top-level process holds it: the command re-execs itself under
  `flock -o ~/.local/state/dotfiles/operation.lock`, so the lock descriptor is
  closed before the command runs and no descendant (vendor installer, logger,
  surviving background process) can inherit it and keep the lock alive
  ([flock(2)](https://man7.org/linux/man-pages/man2/flock.2.html)). The `flock`
  process releases it when the command exits; a re-exec after `git pull`
  keeps the same process, so the lock spans it.
- The holder writes its run id and pid into the lock file and exports
  `DOTFILES_OPERATION=<run id>`. A participating dotfiles command started
  inside the operation (setup from `update`, `ai-config` from an installer,
  update's own verify) joins it when the id matches and the holder pid is
  alive, and never takes or releases the lock itself.
- A standalone `verify` waits briefly for the lock and otherwise reports "an
  operation is in progress" as incomplete.
- The existing state lock keeps protecting individual writes inside an
  operation.

### Refresh

**Environment producer.** A bounded script, not a login shell: it runs
`bash --noprofile --norc`, unsets the guards, sources only Part 1 of
`entry/profile.sh` and `shell/env.sh` with direnv and user startup disabled,
and prints the variables dotfiles manages. A declared list says which those
are:

- *owned* (LESS, PAGER, EDITOR, PROJECTS_DIRS, RIPGREP_CONFIG_PATH,
  `_DOTFILES_*`): set from the layers below, never from an inherited value, so
  nothing needs to remember which default was published where.
- *respected* (XDG roots, TERM): inherited values win; dotfiles never changes
  their defaults, so they cannot go stale.
- *PATH*: the segments dotfiles added last time are replaced with the new set;
  other segments are kept in place.

**Environment layers.** Owned variables are resolved in this order, each layer
overriding the one before, in every shell:

1. Repo defaults: `shell/env.sh`, assigned unconditionally.
2. Machine settings: `~/.shell.env` (new, untracked), environment only, read
   by every shell including non-interactive agent shells.
3. Project activation: direnv. `entry/profile.sh` runs `env.sh` before the
   direnv step in `shell/env-runtime.sh`, the reverse of today's order
   (`entry/profile.sh:76-77`), so an allowed `.envrc` keeps its values.

`~/.shell.local` stays the interactive layer (aliases, functions, keybindings,
prompt). The rule: what a program or agent needs goes in `~/.shell.env`; what
only a prompt needs goes in `~/.shell.local`. Secrets stay in `~/.shell.local`
unless agents should have them.

**tmux.** Refresh targets one server: `$TMUX`'s, or the one named by
`DOTFILES_TMUX_SERVER` (shared with `bin/theme-switcher:38-46`); with no server
it skips tmux. It applies the producer's result to the global environment, and
for each session reports (does not overwrite) a managed variable the session
overrides with a different value. It sets `DOTFILES_DIR` from `install-path`,
sources `~/.tmux.conf`, re-wires the badge when enabled, and runs
`theme-switcher tmux-init`. Bindings, hooks, and appended options retired from
the config need explicit cleanup in `tmux.conf`, as it already does for some
(`configs/tmux.conf:16-20`, `:96-100`, `:130-141`); refresh does not pretend
otherwise. If the server's `#{version}` differs from the installed client,
refresh reports a server restart as a health finding.

`tmux.conf` also unsets both guards from the global environment when it loads.

**Reload.** `reload` replaces the shell with a fresh login shell in place
(`exec $SHELL -l`): it appends history first, keeps the working directory, and
refuses while background jobs exist. A fresh shell is correct by definition, so
there is no definition tracking: removed aliases, functions, exports, options,
and keybindings are simply gone. What a reload loses is session state:
unexported variables and anything defined by hand. `reload --soft` keeps
today's re-source-in-place behavior (clearing every guard first) for when that
matters; it adds and changes definitions but cannot remove them, so a
soft-reloaded shell stays stale (see Staleness).

### Staleness

Staleness is persistent state, not a diff of one refresh.

- For each consumer (shell code, tmux config, each AI CLI, nvim), state records
  the desired digest of its inputs (relevant repo files, generated files,
  local config such as `~/.shell.local`, and the installed executable's
  identity) and a **change event** each time a dotfiles operation changes it:
  the pull, the write, or the binary replacement, timestamped when it
  happened.
- Each interactive shell writes
  `$XDG_RUNTIME_DIR/dotfiles/shells/<pid>-<start-time>` with its digest when it
  starts; a `reload` is a new shell image in the same process, so it rewrites
  the record. Inside and outside tmux alike; nested shells do not overwrite
  each other. Dead entries are swept by refresh.
- For other programs, a process that started before its consumer's last
  change event is stale until it restarts. Binary upgrades count. OpenCode's
  shared service is checked the same way. A change dotfiles did not make (a
  hand edit noticed later) has no reliable time, so processes are reported as
  "possibly stale" for it rather than stale.
- A shell is current when its record's digest matches the desired one.
  `reload --soft` marks the record `soft` without updating the digest, so a
  soft reload never makes a shell look current and a second one cannot hide
  anything; only a real reload or a new shell clears it.
- Coverage limits are reported (no runtime dir, unreadable process start time)
  rather than treated as current.

Verify's running section and refresh's report both read this state, so a
second refresh still lists a stale process.

### Update

`dotfiles update`:

1. Take the operation lock; it is held through re-exec and by every child.
2. Preconditions: on a branch with an upstream, clean tree, the checkout is the
   install path (not another worktree), not detached. Ahead-only: skip the
   pull, say so, continue. Diverged: stop.
3. `git pull --ff-only`, then re-exec the new `bin/dotfiles`. New files are
   already visible to new processes from this moment; re-exec avoids mixing old
   and new scripts, and there is no machine rollback.
4. Apply's component phase with the profile, after migrating the profile
   schema if needed.
5. With `--upgrade`, run each selected component's update operation.
6. Apply's config phase, so version-dependent configs and caches follow any
   upgrade.
7. `refresh` (once, after every binary and file change), then `verify`.
8. Report the revision, what completed, remaining findings, and any pending
   journal. Exit per the outcome table.

The run is logged, ledger diff included.

### Upgrade

`--upgrade` is opt-in (it needs sudo and pulls unreviewed versions). It covers
only what is not pinned: apt packages other than sbx, the AI CLIs, Pi, and
rustup itself.
Pinned tools change only through a commit to `versions.lock`.

- Installers gain an `--update` operation; `run_installer` passes the operation
  instead of relying on the global force bit. `rustup self update` and
  `pi update` run through it and are recorded.
- apt: one `apt-get update`, then
  `apt-get install --only-upgrade --no-remove` for every package in the sets
  the profile selects (core, dev, docker, xrdp, and the per-tool packages).
  Selection enrolls a package for upgrades regardless of who first installed
  it. `--only-upgrade` keeps unselected names from being requested, but apt
  still resolves dependencies, so new dependencies are allowed and `--no-remove`
  forbids removals. The plan shows the simulated transaction (`apt-get -s`),
  including every package outside the selected names that it would install or
  upgrade. Held packages are skipped and reported; sbx is pinned, so
  `--upgrade` never touches it.
- Node, the Rust toolchain, and sbx are pinned, so `--upgrade` does not move
  them. Project-specific Node versions and toolchains are never changed.

### Commands

| Command | Does |
|---|---|
| `dotfiles update [--upgrade]` | As above. |
| `dotfiles verify [-v] [--latest] [--smoke]` | All sections, read-only except `--smoke`. |
| `dotfiles apply [--only X,Y] [--dry-run] [--no-refresh]` | Converge disk to the checkout and profile, then refresh; no pull. |
| `dotfiles refresh [-v]` | Running processes only: tmux environment and config, badge, theme; staleness report. |
| `dotfiles profile [--add X\|--remove X\|--tier T\|--propose]` | Show or change intent; validate, save, plan, apply. |
| `dotfiles bump <tool> [tag]` | Move a pin and its digests; edits files, never commits. |

`-v` lists every check, passing ones included. Verify sections: checkout,
profile, components, configs, AI, work host and Tailscale (health), running,
and upstream (`--latest`, advisory). Today's `verify`, `diff-config`,
`ai-config --check`, and `check-updates` are refactored to emit records and
stay as wrappers until nothing calls them.

### Maintenance: scheduled dependency review

A scheduled Claude job runs against the GitHub repository:

- **Monthly review.**
  1. Gather: `check-updates --outdated --json` lists every pin that is behind;
     the job reads release notes, changelogs, and security advisories for
     those and for the unpinned apt-repo tools.
  2. Judge each candidate: breaking changes, config the repo must adjust
     (renamed tmux options, deprecated Neovim settings), security relevance,
     and the 14-day cool-down. An sbx bump is marked "needs kit validation"
     and carries the kit header updates (`kits/`) in the same pull request.
  3. Apply with `dotfiles bump <tool> <tag>`, never by editing the lock. The
     tool has one handler per artifact kind, each using that source's own
     trust mechanism and checking both architectures before writing:
     - GitHub releases (eget tools, neovim, tmux, the eget and nvm
       bootstraps): GitHub's published digests;
     - Node: nodejs.org's signed `SHASUMS256.txt`, recording the bundled npm
       version;
     - Rust toolchains: the channel manifest for both architectures;
     - aws-cli: the signed versioned zip, as the installer verifies it;
     - git commits (Neovim plugins, vim-plug): the resolved commit, and for
       vim-plug the file digest;
     - sbx: the exact apt package version available for both architectures.
  4. Open a pull request: one commit per tool with config changes alongside,
     a written rationale per bump, and a list of what it chose not to bump
     and why, including notable changes in unpinned tools.
- **Weekly security check.** The same job in a narrow mode opens a pull request
  only when a pinned tool has a security advisory, so a fix does not wait up to
  a month. It may skip the cool-down only for a release that fixes an advisory
  affecting the pinned version, and says so in the pull request.

The judgment is the agent's, the digests and checks are tested code, and the
merge is the owner's. After merging, `dotfiles update` brings each machine to
the new pins. CI runs the suite on every such pull request.

## Alternatives considered

- **chezmoi / yadm / GNU stow** manage files only; tool installation,
  ownership, and pins would stay ours, and live symlinks would go.
- **Nix + home-manager** solves pinning and rollback but needs `/nix`, which
  rules out the managed machines the base tiers exist for.
- **Rewrite the engine in Python.** The bash tier must run on a bare machine
  without Python; revisit only for the parts that run after it.

## Plan

Each phase lands with the suite green. Regression tests come before the
behavior they protect.

**Phase 0: bounded fixes**

- tmux.conf unsets the guards on load; `reload` clears all guards and re-runs
  the profile under zsh; docs say plainly what reload does not undo.
- Environment layers: `shell/env.sh` sets the owned variables
  unconditionally and runs before direnv; `~/.shell.env` is read after it by
  every shell; README and customization docs describe `.shell.env` versus
  `.shell.local`.
- `reload` becomes a fresh shell in place; `reload --soft` keeps the old
  behavior.
- Ledger: keep `package-manager` on apt skips; stop hard-coding zsh `ok`;
  resolve gcloud past the snap shim; clean version strings.
- Enable/start docker only when it is not already enabled and active.
- On a failed replacement, attempt bounded reconciliation; clear the journal
  only after the resulting state is validated and recorded; otherwise keep it
  and block only the mutations it affects.
- Audit `fn || FAILED=true` call paths for unchecked fallible commands.
- `--work` skips sbx, its KVM/builder steps, and its verify checks where sbx is
  not applicable; Docker readiness is split out and still verified; README and
  the work-tier issue change with it.

**Phase 1: profile, observation, thin update**

- Profile with the rules above; `dotfiles profile` (show, add, remove, tier,
  propose).
- The outcome classes and record format; `--observe` for installers and engine
  observation for eget/apt, read-only; `dotfiles verify` built on them.
- Regression coverage for per-tool AI flags, external tools, unsupported
  platforms, custom XDG roots, moved and downgraded pins, and partial failure.
- The operation lock, taken by setup and every changing command.
- A thin `dotfiles update`: lock, preconditions, pull, re-exec, today's setup
  with the profile, the Phase 0 tmux guard fix, verify. It claims only that.
  Not yet: an exact dry-run, config retirement, staleness tracking, nvm
  converging on a moved pin, the new Node/Rust/aws-cli pins, sbx hold receipts
  (all Phase 2), or editor-plugin management.

**Phase 2: apply, versions, config state**

`versions.lock` with every consumer moved, extracted-binary digests for eget
tools, and digests for the eget, nvm, and vim-plug bootstraps; new pins for
Node, the Rust toolchain, and aws-cli; nvm and sbx converge on moved pins;
sbx hold receipts, with the one-time adoption prompt; editor plugins managed
when the profile enrolls them; registry order, `needs`, `policy`, `configure`; decisions from
observations; projected dry-run; `--only`, `--reinstall`, `--overwrite-configs`;
`deployed.tsv` and retirement; AI three-way retirement; configuration steps
moved out of installer early exits.

**Phase 3: refresh and full update**

Environment producer, tmux scope and version check, change events and
staleness state; apply gains its trailing refresh;
then `update` with `--upgrade` between apply's phases.

**Phase 4: maintenance**

`dotfiles bump` with its per-kind handlers (multi-architecture checks before
writing the lock, 14-day cool-down), then the scheduled review (see
Maintenance).

## Review disposition

How each point of [the review](setup-update-redesign-review.md), and of its
second round, is handled.

| Review point | Disposition |
|---|---|
| 1. Do not clear failed transactions | Accepted. Phase 0 reconciles within bounds and keeps the journal unless the result is validated and recorded; errexit audit added to Phase 0. |
| 2. AI selection broadening; order is not a dependency contract | Accepted. Selection and dependencies: explicit order, `needs`, `--only` reports blockers; per-tool AI regression tests in Phase 1. |
| 3. Profile semantics and migration | Accepted. Machine profile: merge-only setup writes, explicit removal, durable opt-outs, ledger-derived proposal needing confirmation. |
| 4. `--check` conflates states | Accepted. Component observation: structured fields, exit 3 for "could not observe", projected dry-run with `unknown`. |
| 5. Artifact model for `versions.lock` | Accepted. Versions and artifacts: one authority, identity per kind, bootstrap digests, bash parser. |
| 6. Policy separate from ownership and configuration | Accepted. Separate `policy` / `backend` / `configure`; foreign installs are advisories; per-component force rules kept. |
| 7. Clean login shell is unsafe | Accepted. Bounded environment producer; owned / respected / PATH rules. |
| 8. Global tmux environment is not enough | Accepted. One targeted server, session overrides reported, server version check, no claim that sourcing removes retired bindings. |
| 9. Staleness must persist and track processes | Accepted. Per-process records and change events; `reload` is a fresh shell, `--soft` stays stale (round three). |
| 10. Verify ≠ apply has nothing to do | Accepted. Outcomes: convergence, health, advisory, with exit codes; records instead of parsed text; `--smoke` stays separate. |
| 11. Exact-identity retirement | Accepted. Config state and retirement: exact link or digest match, per-entry records, approved roots, three-way AI retirement. |
| 12. `--upgrade` actions and coverage | Accepted. Upgrade: installer `--update` operation, package sets of the selection, holds reported, Node split from nvm. |
| Finding corrections (table) | Accepted; the Findings section was rewritten. |
| Phase order | Accepted, with one deviation: a thin `dotfiles update` with stated limits lands in Phase 1, because easy updating is the goal. |
| Refresh invoked twice | Fixed: refresh runs once, at the end of the command given; `update` calls apply with `--no-refresh` and refreshes after any upgrade. |

Second round:

| Review point | Disposition |
|---|---|
| 1. Invocation scope vs saved intent; dry-run writes | Accepted. Setup does what its flags say and merges them; `--config` stays config-only; only `dotfiles` commands apply the whole profile; `--dry-run` never writes it. |
| 2. vim-plug check; eget tag → binary digest | Accepted. vim-plug by file sha256; the lock records each eget tool's extracted-binary digest per architecture. |
| 3. Stale inherited defaults | Accepted, solved differently: owned variables are set from layers, never inherited, so no publication history is needed (layers refined in round three). |
| 4. Restart warning lost on second reload | Accepted; superseded in round three: `reload` is now a fresh shell, and `--soft` never clears staleness. |
| 5. Lock every competing writer | Accepted. One operation lock across all changing commands, inherited through re-exec and children; verify takes it shared. |
| 6. `ai=all` vs `--remove pi` | Accepted. `ai.exclude`. |
| 7. Upgrades after config render | Accepted. Apply has component and config phases; upgrades run between them. |
| 8. Package-set ownership; hold provenance | Accepted. Selected sets are enrolled regardless of who installed them; sbx holds carry receipts. |
| 9. Observation failure outcome | Accepted. "incomplete" class, exit 3; precedence convergence, incomplete, health. |
| 10. Docker checks under skipped sbx | Accepted. Docker readiness split from sbx/KVM readiness. |
| xrdp on WSL is supported | Corrected; the example is now `--azure` on Ubuntu 26.04. |
| Timestamp staleness | Accepted. Recorded change events; changes dotfiles did not make yield "possibly stale". |
| Phase 1 caveats | Accepted. nvm pin convergence, the new pins, sbx hold receipts, and editor plugins listed as not yet. |

Third round:

| Review point | Disposition |
|---|---|
| 1. Name-set tracking cannot find removed definitions | Accepted; tracking dropped. `reload` is a fresh shell in place; `reload --soft` keeps the shell stale. |
| 2. Unconditional exports overwrite direnv; `.shell.local` misses non-interactive shells | Accepted. Layers: repo default, `~/.shell.env` (every shell), direnv; `env.sh` moves before direnv. |
| 3. sbx compatibility constraint | Accepted. sbx stays pinned and held; receipts; one-time adoption of the existing hold; sbx bumps need kit validation. |
| 4. Inherited lock descriptors | Accepted. `flock -o`: only the top-level holder; participants join by run id and live holder pid; `verify --smoke` exclusive; update's verify joins. |
| 5. `--only-upgrade` boundary | Accepted. `--no-remove`, new dependencies allowed and shown in the simulated transaction. |
| 6. Isolated Rust and npm observation | Accepted. `rustup default` from a neutral directory without overrides or auto-install; bundled npm version recorded and checked. |
| 7. Bump handlers by artifact kind; security cool-down | Accepted. Per-kind handlers with each source's trust mechanism; the security check may skip the cool-down only for a fix to an advisory affecting the pin. |
| Exit precedence per command | Accepted. Per-command table; converged requires complete observation. |
| Azure example wording | Corrected: excluded by this repository's registry. |

## Decisions

1. `--upgrade` is opt-in.
2. Configs whose source left the manifest are retired automatically when the
   target still matches exactly what was deployed, with a backup and a report.
3. No status-bar indicator; refresh and verify report staleness, and `-v`
   shows every check.
4. `--work` installs what the platform supports and skips sbx where it is not
   applicable; explicit requests still fail. This settles the
   [work-tier decision](work-tier-sandbox-boundary.md).
5. Layers: `update` = pull + apply; `apply` = disk + refresh; `refresh` =
   running processes only. Refresh runs once per command.
6. Profile changes are validated, saved, planned, then applied, from either
   `dotfiles profile` or setup flags. Setup flags only add; removal is explicit
   and never uninstalls.
7. Dotfiles-owned environment variables (EDITOR, PROJECTS_DIRS,
   RIPGREP_CONFIG_PATH, LESS, PAGER) resolve as repo default, then
   `~/.shell.env` (every shell), then direnv. Inherited values no longer
   override them. `~/.shell.local` is for interactive shells only.
8. `--upgrade` covers every package in the selected sets except sbx, whoever
   installed it, with `--no-remove` and the resolved transaction shown.
9. Pin everything dotfiles downloads itself (adding Node, the Rust toolchain,
   and aws-cli), plus sbx, which kits require at an exact version; leave other
   apt-repo and distro packages to apt, and AI CLIs and Pi to their updaters.
   Holds are moved only with a receipt.
10. Pins move through a scheduled Claude review: monthly bumps by pull
    request with written rationale, plus a weekly security-only check,
    replacing the planned weekly CI issue.
11. `reload` starts a fresh shell in place; `reload --soft` re-sources and
    leaves the shell marked stale.
