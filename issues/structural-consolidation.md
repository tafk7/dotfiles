# Spec: structural consolidation

**Status:** implemented on branch `structural-consolidation`; not merged.
**Problem:** the repo carries employer identifiers in public tracked files,
compatibility code for migrations that have finished, four copies of checkout
discovery, a selection model that exists twice in `setup.sh`, and a registry
spread across 20 parallel arrays whose verify commands run through `eval`. Each
new tool or capability costs more edits than it should, and every hot path
carries dead branches.
**Goal:** remove what is finished, collapse what is duplicated, and make the
next tool or capability a one-place change — without changing any user-visible
flag, tier, or installed result.

Work in phases, in this order. Each phase is one commit (or a small series),
lands with the full suite green, and is independently revertible.

| Phase | Item | Why here |
|---|---|---|
| 0 | Preflight | Establish a green baseline and confirm migration is complete |
| 1 | Employer identifiers out of tracked files | Independent, and exposure grows with every push |
| 2 | Retire compatibility code | Pure deletion; shrinks the surface phases 3–5 touch |
| 3 | One checkout-discovery implementation | Only simple once phase 2 removes `bridge.sh` |
| 4 | One selection model in `setup.sh` | Fixes the capability vocabulary the registry will encode |
| 5 | Registry as one record per tool; no `eval` | Largest change; lands on the settled vocabulary |

General rules for every phase:

- Develop in a separate worktree; don't run setup against the live HOME
  (see [maintenance](../docs/maintenance.md)).
- Behavior-preserving unless a step says otherwise. `./setup.sh --help`, tier
  contents, flag semantics, and `bin/verify` results must not change.
- Run the whole suite (see [testing](../docs/testing.md)), shellcheck, and
  `plugins/sync-shared.sh --check`. For phases 1, 2, and 3, which touch files
  read during shell startup, also run `tests/startup-benchmark.py` against the
  pre-phase revision; startup must not regress. (The registry is never loaded
  at shell startup, so phases 4 and 5 need no benchmark.)
- Update docs and comments in the same commit as the code they describe.

---

## Phase 0 — Preflight

1. Make `tests/validate-structured.sh` pass. It rejects executable files under
   `configs/`, but two portable AI assets currently carry the bit:
   `configs/ai/claude/statusline.sh` and
   `configs/ai/codex/skills/thread-handoff/scripts/extract_thread.py`. Invoke
   both through their interpreter — `bash ~/.claude/statusline.sh` in
   `configs/claude-settings.json`, `python3 scripts/extract_thread.py` in the
   skill's `SKILL.md` — and clear the bit, so the "configuration is data" rule
   keeps no exceptions.
2. On every machine that uses this checkout, confirm migration is complete:
   - `${XDG_STATE_HOME:-~/.local/state}/dotfiles/install-path` names the intended
     checkout;
   - `${XDG_STATE_HOME:-~/.local/state}/dotfiles/theme.tsv` exists **and
     validates** (the legacy theme reader in `lib/theme-resolve.sh` also runs
     when the file is present but invalid), and `bin/verify --installed` passes;
   - no component ledger still depends on the 2026-09 ownership migration
     (`migrations/2026-09-ownership/adopt.sh` without `--apply` reports nothing
     to do);
   - `~/.local/bin/codex` is not a regular file (the legacy direct-binary
     layout phase 2 stops migrating).
   Record the result privately. Phase 2 does not start until every machine
   passes.

**Done when:** the suite is fully green on `main` and every machine passes the
checks above.

---

## Phase 1 — Employer identifiers out of tracked files

The repo is public. Tracked files identify an employer and its internal hosts:

- `configs/gitconfig-azure`: an organization-specific `*.visualstudio.com`
  credential host
- `bin/git-credential-azdo`: the same host in the install comment
- `shell/tools/git.sh`: the employer clone helper (`gcl-<employer>`), its
  `GH_<EMPLOYER>_USER` variable, its `github.com-<employer>` SSH alias, and the
  employer name in its comment and success message
- `shell/shortcuts-index.tsv`: the helper's row
- `docs/customization.md`: the helper's section, including its token note
- `issues/git-profiles.md`: employer profile examples and the helper's
  transition item

This spec deliberately names none of them; the check in step 4 would flag it
otherwise.

Steps:

1. Delete the employer clone helper from `shell/tools/git.sh` and its row from
   `shell/shortcuts-index.tsv`. On the work machine, move the function
   unchanged into the untracked `~/.shell.local` until
   [git profiles](git-profiles.md) lands. Do not add a generic tracked
   replacement: git profiles replaces the per-profile SSH alias with
   `core.sshCommand`, replaces shell variables with a `[profile]` section in an
   untracked profile file, and drops the `gh repo set-default` step. A generic
   helper built on the current mechanism would be public API that spec removes.
   Update git profiles' transition item for the helper accordingly.
2. Keep only `https://dev.azure.com` in `configs/gitconfig-azure`. Machine-local
   organization hosts go in `~/.gitconfig.local`; document that in
   `docs/customization.md` and `docs/work.md`, and use a placeholder in the
   `bin/git-credential-azdo` comment.
3. Replace employer names in docs, comments, and issue examples with neutral
   placeholders (`work`, `example.visualstudio.com`).
4. Add a check to `hooks/pre-commit` that fails on a small denylist of employer
   identifiers kept **outside** the repo (a path in an environment variable,
   skipped when unset), so the check itself doesn't reintroduce them. Match
   whole words so unrelated tokens such as `kvm_amd` or `amd64` don't trip it.
   CI can run the same check only if the list is supplied as a repository
   secret; without one, the check is local-only, and that is acceptable.
5. Decide separately whether history needs rewriting. Removing the strings from
   `main` does not remove them from Git history or existing clones and forks,
   and history already identifies the employer through commit metadata — author
   emails (including one derived from a work hostname) and at least one commit
   subject — not only through file contents. Cleaning `main` therefore mainly
   reduces code-search exposure. A rewrite would need an author mailmap and
   message edits as well as content filtering, changes every commit hash, and
   still cannot reach existing clones. That decision belongs to the owner; do
   not rewrite history as part of this phase.

**As built, superseded:** Azure DevOps is no longer used at work, so a
follow-up commit parked the integration instead: `configs/gitconfig-azure`, the
generated include, the helper link, and its verify check are gone, and
`bin/git-credential-azdo` plus a `~/.gitconfig.local` snippet in
`docs/work.md` remain for manual use.

**Done when:** the denylist check passes on the whole tree, the moved helper
behaves as before on the work machine, and the Azure helper still authenticates
`dev.azure.com` and the locally configured organization host.

---

## Phase 2 — Retire compatibility code

Requires phase 0's migration checks. Remove, together with their tests:

- **Checkout bridge:** the `generated/bridge.sh` reader blocks in
  `entry/bash.sh`, `entry/zsh.sh`, and `entry/zshenv`. Nothing writes or
  verifies the file any longer; only these three readers remain.
- **Legacy theme state:** the `generated/theme*.sh` reader in
  `lib/theme-resolve.sh` (`DOTFILES_LEGACY_GENERATED_DIR`),
  `generated/compatibility/README.md` and its `.gitignore` exceptions, the
  migration cases in `tests/theme-system.sh`, `tests/state.sh`, and
  `tests/theme-refresh.sh`, and the `DOTFILES_LEGACY_GENERATED_DIR` setup in
  `tests/startup-benchmark.py`.
- **Ownership migration:** `migrations/2026-09-ownership/`. Also remove the
  "ownership inferred from location" note in `docs/maintenance.md` if no ledger
  still carries such records.
- **Retired wrappers:** the `claude-vsc` / `codex-vsc` unsets in
  `shell/tools/claude.sh` and `shell/tools/codex.sh`.
- **Codex legacy binary migration:** the "legacy direct Codex binary" path in
  `installers/install-codex.sh` and its cases in `tests/install-codex.sh`.
- **Old alias guards:** `unalias` lines that exist only to upgrade from alias to
  function definitions (`reload`, `myip`, `nclean`, python helpers), and the
  "reload from legacy aliases" case in `tests/shell-behavior.sh`. Keep any that
  guard against a real name clash; check `tr` in `shell/tools/tmux.sh`, whose
  function deliberately shadows the standard utility, before removing it.
- **`bin/verify --tier ai`:** `tests/verify-profiles.sh` calls it a legacy
  compatibility alias, but `bin/verify --help` documents it. Either remove it
  with its test, or keep it and drop the "legacy" label.

Also update `docs/maintenance.md` ("Compatibility code") and
`docs/theme-system.md` (legacy reader mention). After the phase lands, each
machine may delete its untracked `generated/bridge.sh`, `generated/theme.sh`,
`generated/theme-state.sh`, and `generated/theme-overrides.sh`; nothing reads
them.

**Done when:**

- `git grep -nE 'bridge\.sh|LEGACY_GENERATED|generated/theme|claude-vsc|codex-vsc|2026-09-ownership' -- ':!docs/history' ':!issues'`
  returns nothing;
- `git grep -nw legacy -- ':!docs/history' ':!issues'` returns only these
  intentional uses: the apt `.list` comment in `lib/install.sh`, the
  hard-coded checkout-path check in `tests/validate-structured.sh`, and the
  tmux 3.2 palette case in `tests/theme-system.sh`;
- the suite and benchmark pass.

---

## Phase 3 — One checkout-discovery implementation

Today `entry/profile.sh`, `entry/bash.sh`, `entry/zsh.sh`, and `entry/zshenv`
each resolve `DOTFILES_DIR` with slightly different fallbacks. A file inside the
checkout cannot hold the shared fallback: the fallback runs exactly when the
checkout's location is unknown. `~/.profile` is at a fixed path, and
`entry/bash.sh` and `entry/zshenv` already source it, so the fallback lives
there.

Target contract, documented once in `docs/architecture.md` ("valid" means
`$DOTFILES_DIR/shell/env.sh` exists):

1. The entry file's own symlink, when it resolves to a valid checkout.
2. Otherwise an already-set, valid `DOTFILES_DIR`.
3. Otherwise `${XDG_STATE_HOME:-~/.local/state}/dotfiles/install-path`.
4. Otherwise `~/dev/dotfiles`.

An inherited `DOTFILES_DIR` never overrides a resolvable symlink. This matches
today's bash and zshenv behavior and keeps two cases correct: a test HOME linked
to a worktree, launched from a shell that exports the live checkout, and new
tmux panes after a checkout switch.

Steps:

1. In `entry/bash.sh` and `entry/zshenv`, resolve the symlink into a temporary
   variable and export it as `DOTFILES_DIR` only when it is valid; otherwise
   leave `DOTFILES_DIR` untouched. Zsh keeps `${file:A:h:h}`; bash keeps
   `readlink -f` on `BASH_SOURCE`.
2. Implement steps 2–4 once, in Part 2 of `entry/profile.sh`: keep a valid
   `DOTFILES_DIR`, else read `install-path`, else use the default. It must stay
   POSIX and fork-free (dash reads the file, though dash skips Part 2).
3. Remove `entry/zsh.sh`'s fallback block. `~/.zshenv` and `~/.zshrc` share the
   `zsh` owner in `CONFIG_MAP` (`lib/config.sh`), so they are always installed
   together. If kept anyway, it follows step 1.
4. Add a test covering all four resolution steps in bash and zsh against the
   same fixture, without passing `DOTFILES_DIR` explicitly (which
   `tests/shell-behavior.sh` always does). Include an inherited `DOTFILES_DIR`
   naming a different valid checkout alongside a resolvable symlink; the
   symlink must win. For dash, assert only that sourcing `~/.profile` succeeds
   and leaves `DOTFILES_DIR` unset.

**Done when:** the fallback exists once in `entry/profile.sh`; the new test and
`tests/shell-behavior.sh`/`tests/project-environment.sh` pass; startup does not
regress.

---

## Phase 4 — One selection model in `setup.sh`

Today selection exists twice: the booleans `INSTALL_AI`, `INSTALL_RDP`,
`INSTALL_TAIL`, `INSTALL_AZURE`, `INSTALL_GCLOUD`, `INSTALL_AWS`, and
`AI_ALL`/`AI_TOOLS`, plus the `capability_selected` helper. The chain
`INSTALL_RDP || INSTALL_TAIL || INSTALL_AZURE || …` is repeated through
`phase_verify_system`, `phase_install_packages`, the banner, and the success
message.

Steps:

1. First, as its own commit on the pre-phase code, add a characterization test.
   For a matrix of flag combinations, it records `--help`, the banner, the
   success line, the selected components, and the system requirements checked.
   The refactor must keep it passing unchanged.
2. Parse flags into `INSTALL_TIER` plus one set of selected capabilities
   (`ai`, `rdp`, `tail`, `azure`, `gcloud`, `aws`) and one set of explicitly
   selected AI tools. `--ai` selects every registry tool with the `ai`
   capability; `--claude` etc. select individual tools; `--full` stays exactly
   `--work --ai`. `agent-badge` is also a registry capability (`jq`), on by
   default with AI and controlled by `--agent-badge`/`--no-agent-badge`; either
   give it a table row as a capability that depends on `ai`, or state in the
   table's comment why it stays separate.
3. Describe each capability once, in a table: its flag, whether it needs APT,
   curl, sudo, or systemd, its supported platforms, its install function, and
   its banner/summary label. Store it as an indexed array; its order is the
   banner and success-line order. Verification, installation dispatch, the
   banner, and the success line all iterate that table.
4. Replace the repeated boolean chains with helpers such as
   `any_capability_selected` / `selected_capabilities_needing apt`.
5. Update `lib/install.sh` and the tests that set or assert `INSTALL_*`,
   `AI_ALL`, or `AI_TOOLS` directly (`tests/argument-parsing.sh`,
   `tests/work-selection.sh`, `tests/badge-dependency.sh`). Those tests are
   rewritten against the new selection helpers; the characterization test is
   the unchanged guard.
6. **Decision point, not an implicit change:**
   [work-tier sandbox boundary](work-tier-sandbox-boundary.md). If the owner
   decides to split sbx/KVM into its own capability, do it as a follow-up commit
   with its own compatibility note and tests. Otherwise leave `--work` as is.

**Done when:** each capability is named in one table plus its install function;
the characterization test passes unchanged, so `--help`, the banner, and the
success line are byte-identical to before; a new capability needs only a table
row and an install function.

---

## Phase 5 — Registry as one record per tool; no `eval`

Today `lib/registry.sh` defines 20 `TOOL_*` associative arrays, some filled by
loops over hard-coded name lists, and seven call sites in six files `eval`
strings from `TOOL_VERIFY` (`lib/install.sh` twice, `lib/config.sh`,
`bin/verify`, `bin/check-updates`, `bin/uninstall-tool`, `bin/cheatsheet`).

Steps:

1. Before changing anything, capture on a real machine the output of
   `bin/verify --all`, `bin/cheatsheet tools`, `bin/uninstall-tool --list`, and
   `bin/check-updates` at the pre-phase revision.
2. Define tools in two heredoc tables parsed once at source time:
   - **Core:** one row per tool with name, binary, method, tier, capabilities,
     platform, arches, Ubuntu versions, APT package, and verify.
   - **Overrides:** sparse `name field value` lines for everything else: eget
     repo, update source, relative binary, version flag, timeout, companions,
     ownership roots, update contract, uninstall paths, removal mode,
     removal-requires-sudo, and removal instructions.

   Empty cells and absent overrides take documented defaults. Derive them from
   the method where possible, so adding an eget tool really is one row:
   `eget` ⇒ ownership root `~/.local/bin`, update contract `staged-release`,
   uninstall path `~/.local/bin/BINARY`. Other defaults: binary = name, arches
   = both, platform = ubuntu. The value of an override line is the rest of the
   line, so free text with spaces, `&&`, `#`, and `|` needs no quoting. The
   tables are double-quoted strings, so `$HOME` expands where they are defined
   and nothing is evaluated. Parsing must stay cheap; `bin/verify` and setup
   load the registry often. (As built: parsed in memory, because `read` from a
   heredoc costs a syscall per byte; loading takes about 20 ms against 6 ms
   before, on a loaded host, and never runs at shell startup.)
3. Populate the existing `TOOL_*` arrays from the parsed records, so callers
   don't change. **Decision while implementing:** the arrays stay the read
   interface, read-only by convention. Accessor functions would need a command
   substitution, and so a subshell, per lookup in loops that `bin/verify` and
   setup run over every tool. Callers include `lib/install.sh`, `lib/config.sh`, `lib/state.sh`,
   `installers/install-sbx.sh`, the `bin/` tools, `tests/registry.sh`,
   `tests/uninstall-safety.sh`, `tests/state.sh`, the embedded bash in
   `tests/eget-selection.py`, and `.github/workflows/ci.yml` and `arm64.yml`.
4. Replace `TOOL_VERIFY` strings with a verify type plus argument:
   - `command [EXTRA…]` (default): the binary, its companions, and any extra
     commands are on PATH. Rust uses `command cargo`, which leaves companions
     (which also drive installation and removal) unchanged.
   - `runs`: the binary is on PATH and exits 0 with its version flag (default
     `--version`), under the tool's timeout when one is set. Used by codex, pi,
     aws-cli, and sbx (`version`, 10 s).
   - `service-active UNIT`: xrdp.
   - `file-nonempty FILE`: nvm (`~/.nvm/nvm.sh`).
   - `function NAME`: a named predicate in `lib/registry.sh` for checks no type
     expresses. Today that is ripgrep only: it prefers the managed
     `~/.local/bin/rg` and otherwise rejects `rg` copies private to Codex or VS
     Code extensions.

   Implement `tool_is_present NAME` once and replace all seven `eval` sites
   with it.
5. Keep removal instructions and uninstall paths as override fields,
   preserving the validation `bin/uninstall-tool` applies to them.
6. Extend `tests/registry.sh`: every record parses, has a known method, a known
   verify type, and a tier or capability; every override names a known tool and
   field. The two-way `eget.toml` ↔ registry check already lives in
   `tests/eget-selection.py`; keep it there.
7. Rewrite the "adding a tool" recipes in `docs/customization.md` to the new
   form.

**Done when:** adding an eget tool is one core row plus one `eget.toml` block;
`git grep -nw eval -- bin lib setup.sh` lists only audited uses unrelated to
registry data; the four commands from step 1 produce the same output as the
captured baseline on the same machine.

---

## Out of scope

- Moving `lib/state.sh` to Python and simplifying the theme system. Both were
  identified alongside these items and deserve their own specs.
- Implementing [git profiles](git-profiles.md). Phase 1 only moves the employer
  clone helper out of tracked files until that spec lands.
- Rewriting Git history (see phase 1, step 5).
- Choosing a license.
