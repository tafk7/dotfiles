# Repository evidence and comparison notes

Read the installed revision's `docs/architecture.md`, `docs/customization.md`,
`docs/maintenance.md`, and `docs/ai-configuration.md` where relevant. Inspect
the target's versions of affected contracts as data with `git show`.

## Machine evidence map

State root: `${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}`.
Read versioned TSV/JSON as data; never source a state file. Absence of a receipt
does not grant permission to replace an artifact.

| Evidence | Purpose |
|---|---|
| `install-path`, resolved rc links, `DOTFILES_DIR` | Identify the active checkout and conflicting discovery paths. A valid rc link takes precedence over an inherited directory; `entry/profile.sh` handles fallback discovery. |
| `profile` | Intended tier (`config`, `bash`, `dev`, `work`), capabilities, AI selection/exclusions, `no-git` and `no-hooks`. Flags add intent; removing intent does not uninstall anything. |
| `preferences.tsv`, `theme.tsv` | Persistent theme and agent-badge choices, independent of tier. |
| `components.tsv`, `holds.tsv` | Observed version/path/status, ownership, update contract, and APT hold receipts. Cross-check reality; a binary under `~/.local/bin` is not proof of ownership. |
| `deployed.tsv` | Exact link/digest/include setup wrote. Config retirement requires matching provenance; preserve a user-modified target. |
| `ai/*.json` | Last-applied enforced/default values and conflicts, needed to predict AI merge and retirement. Treat values as potentially private. |
| `transactions/`, legacy `transaction.tsv`, `operation.lock` | Interrupted replacements or concurrent operations. Inspect existing metadata; do not recover transactions or create/acquire writer locks. An existing lock file alone does not prove an active operation. |
| `changes.tsv`, shell runtime markers, selected log metadata | Explain pending reconciliation and consumers older than a binary/config change. Logs may contain private values; read only necessary evidence. |

`lib/registry.sh` defines applicability, cumulative tiers, capabilities, needs,
install policy, configure steps, ownership roots, and update contracts.
`versions.lock`, `eget.toml`, and plugin pins in `configs/init.vim` describe
versioned artifacts. `lib/config.sh`'s `CONFIG_MAP` defines destinations and
owners, including the portable Git config rendered under
`${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/gitconfig` and included from
`~/.gitconfig`. Base configs apply regardless of tier; tool configs are gated
by owner presence, including external installs. Inspect source files instead
of evaluating target-revision shell declarations.

Machine-local sources to consider when affected:

- `~/.shell.env`, `~/.shell.local`, `~/.shell.local.d/*.sh`: environment and
  interactive overrides; inspect relevant PATH/tool roots and launch flags
  without evaluating shell substitutions or executing commands.
- `~/.gitconfig.local`, `${XDG_CONFIG_HOME:-$HOME/.config}/git/profiles/`, and
  includes: preserve identity, signing, credentials helpers, and per-repo
  routing. Query individual behavior keys; avoid printing identity values.
- `~/.tmux.local.conf`, `~/.ssh/config.local`, `~/.ssh/config.d/*.conf`, and
  `~/.ssh/use-windows-agent`: override ordering and WSL integration. Never read
  private key material. Avoid `ssh -G` when it would execute `Match exec`.
- AI homes: respect `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, and XDG config paths.
  Inspect only affected keys in Codex `config.toml`, Claude `settings.json`,
  OpenCode `opencode.json`/`cli.json`, and Pi settings. System/provider layers
  may affect effective values; the user file alone cannot prove precedence.
- Selected work features: Docker endpoint/context, KVM/group access, sbx pins
  and kits, APT holds, service state, Tailscale enrollment, and
  `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/buildkitd-sbx-kits.toml`.
  Use read-only queries without sudo; skip unselected/unaffected features.
- If `configs/wezterm.lua` changes, the Windows copy is manually deployed.
  Inspect accessible revision evidence (`LC_TAFK_WEZTERM` or the verifier's
  implementation); do not claim an inaccessible Windows copy was checked.

AI policy is a three-way merge, not a byte comparison. Enforced keys win;
defaults follow updates only while the machine holds the last written value.
User-edited or intentionally removed defaults remain local. Moving enforced
keys to defaults hands them over. Removed keys are retired only if unchanged;
`configs/ai/released.json` releases management without deleting their value.
Portable assets are owned whole files. Check malformed files, conflicting
shapes, and symlinked targets before promising a clean merge. Unlisted settings,
credentials, histories, and provider choices stay local.

## Probe and preview caveats

- `bin/diff-config` reports checkout-to-HOME drift, not incoming remote impact.
  Default status output is preferable to `--diff`, which may expose local data.
- `bin/ai-config --check --plugins` and `--dry-run` are check modes; inspect the
  relevant implementation before using them. They reflect their own checkout.
- Ordinary `bin/dotfiles verify -v` documents exits 0 (healthy), 1 (convergence
  needed), 2 (human action), and 3 (incomplete check). Preserve the output and
  status; a nonzero result is useful evidence. It invokes `bash -lc` and sources
  shell environment code, so it is unsuitable when those paths can mutate.
  `--smoke` creates a sandbox; do not run it for this review. `--latest` checks
  upstream releases, a separate question from adoption of remote `main` pins.
- `_observe_probe` in `lib/observe.sh` and `probe_version` in
  `lib/ai_preferences.py` isolate XDG writes because OpenCode's `--version`
  writes cache/log/data. Prefer metadata when a probe's behavior is unknown.
  A version flag alone is not a guarantee of no side effects.
- Setup previews log and rotate logs unless `DOTFILES_SETUP_LOG=0`.
  `dotfiles update --dry-run` fetches in the active repo and previews the
  **current** code without pulling. Neither is part of this review. After
  adoption, a future `DOTFILES_SETUP_LOG=0 <install>/bin/dotfiles apply --dry-run`
  can preview reconciliation under the adopted code.
- A temporary target checkout is not a simulation of this machine. Applying
  there against real HOME would redirect live symlinks and `install-path`;
  applying against an empty HOME loses the local merge/ownership evidence.
  Inspect target code statically. If a future disposable simulation is useful,
  copy only necessary sanitized state and isolate all writable roots/services.

## Compare remote main without changing the installation

Use Git network access or an available repository connector for the actual
remote, following environment permission rules. The following Bash recipe uses
an independent object database; it does not update the source repos' refs,
index, `FETCH_HEAD`, or reflogs. Assign `review_install` to the resolved active
checkout, and run with error handling so a failed fetch cannot leave a stale
target in use. Do not enable shell tracing with a credential-bearing URL.

```bash
set -euo pipefail
review_remote=origin
review_base=$(git -C "$review_install" rev-parse --verify 'HEAD^{commit}')
review_url=$(git -C "$review_install" remote get-url "$review_remote")
review_tmp=$(mktemp -d /tmp/dotfiles-upgrade-review.XXXXXX)
chmod 700 "$review_tmp"
review_git="$review_tmp/objects.git"
git init --bare --quiet "$review_git"
git --git-dir="$review_git" -c core.hooksPath=/dev/null fetch \
  --quiet --no-tags --no-recurse-submodules "$review_url" refs/heads/main
review_target=$(git --git-dir="$review_git" rev-parse --verify 'FETCH_HEAD^{commit}')
review_observed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
git --git-dir="$review_git" -c core.hooksPath=/dev/null fetch \
  --quiet --no-tags --no-recurse-submodules "$review_install" "$review_base"
git --git-dir="$review_git" rev-list --left-right --count "$review_base...$review_target"
git --git-dir="$review_git" log --oneline "$review_base..$review_target"
git --git-dir="$review_git" diff --no-ext-diff --no-textconv --find-renames \
  --stat "$review_base" "$review_target"
git --git-dir="$review_git" diff --no-ext-diff --no-textconv --find-renames \
  --name-status "$review_base" "$review_target"
```

Use `git --git-dir="$review_git" show "$review_target:path/to/file"` and
scoped diffs for affected sources. For divergence, use `merge-base` and both
sides' logs/diffs. Treat a missing merge base, incomplete shallow history, a
missing remote/branch, or a network failure as a limitation. Never substitute
remote default HEAD for `main`. An offline fallback may import the cached
`refs/remotes/origin/main` SHA from the installation into the temporary
database, but must be labeled unverified against the remote.

Read dirty state with `GIT_OPTIONAL_LOCKS=0 git -C "$review_install" status
--porcelain=v1 --untracked-files=all`, then scoped `git diff` and `git diff
--cached` with `--no-ext-diff --no-textconv`. Do not print untracked secret
contents. Recheck installed HEAD and dirty state at the end; a concurrent
change invalidates affected conclusions.

Network access can trigger credential helpers or SSH host-key writes. Reuse
existing read access; if it cannot be used without persistent changes, use a
read-only connector or report the cached comparison and its limitation.
Clean up only the private temporary directory created for this review, never
the install path or any user state. Record SHAs and useful evidence in the
report before removing scratch storage.
