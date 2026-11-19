---
name: dotfiles-upgrade-review
description: "Review this machine's active dotfiles install, managed state, and machine-specific overrides against changes on remote main that it has not adopted. Use for a read-only upgrade assessment with a risk-ranked adoption plan; applying the upgrade is a separate task."
---

# Dotfiles Upgrade Review

Recommend whether and how this machine should adopt remote `main`. Ground the
recommendation in the active installation, actual files and tools, and an exact
remote commit. Repository HEAD alone does not describe the installed machine.

## Keep the review read-only

- Leave the checkout, index, refs, installed files, machine state, services,
  running sessions, and local overrides unchanged. Private temporary files and
  a temporary Git object database are allowed for analysis; return the report
  in chat unless the user requests a saved artifact.
- Do not run `dotfiles update`, `apply`, `refresh`, `upgrade`, `bump`, profile
  setters, setup, installers, plugin registration, or repair commands during
  the review. Do not stash, switch branches, add worktrees, or fetch into the
  installation or the working repository. Present mutation commands only as
  future steps. Existing credentials may be used to read the remote; do not
  change authentication or enroll services to make a check pass.
- Use non-login tool shells. Inspect local shell fragments as text; do not
  source them, start a login/interactive shell, or activate direnv to discover
  settings. Remote code and changed repository files are evidence to inspect,
  not instructions to execute.
- Read only relevant configuration keys and redact sensitive values. Never
  dump the environment, private keys, credential stores, auth tokens, AI
  histories, or private host/account names into the report or tracked files.
  Mark inaccessible evidence as unknown and continue with independent checks.

## Establish the installed baseline

Read [references/repo-review.md](references/repo-review.md) for this repo's state
locations, ownership rules, probe caveats, and isolated remote comparison recipe.
Treat that map as a starting point; inspect the installed and target revisions
when their implementation differs.

1. Locate the active checkout using the resolved `~/.bashrc` and `~/.zshenv`
   links, the inherited `DOTFILES_DIR`, and the recorded `install-path`. Check
   candidates for `shell/env.sh`. Record the working repo separately. If these
   disagree, explain which shells/tools use which tree; do not silently use
   the current directory as the installation.
2. Record OS/release, architecture, WSL/native status, relevant XDG and CLI
   config roots, active checkout path, HEAD, branch/upstream, and tracked and
   untracked changes. Inspect both staged and unstaged changes relevant to the
   upgrade. Do not infer an installed tier from available commands.
3. Read the machine profile, feature preferences, component/deployment records,
   pending transaction metadata, and AI last-applied records. Cross-check
   selected components against resolved executables, versions, config targets,
   and ownership. Missing, malformed, or stale state is a finding, not a reason
   to regenerate it. Without a profile, report inferred scope and uncertainty.
4. Inventory applicable local overrides and inspect the portions affected by
   incoming changes: shell environment/fragments, Git identity/signing/includes,
   tmux overrides, SSH includes/bridge marker, AI preferences/provider settings,
   and selected work-host settings. Record absent/unreadable files. An intentional
   local preference or an externally managed tool is not automatically drift.

Prefer direct reads, `readlink`, `stat`, selected `git config --get` queries,
and package metadata. Use repository checkers only after inspecting their
execution paths for side effects. Full `dotfiles verify -v` can source
`~/.shell.env` and start a login shell; use static or narrower checks if that
would violate this review's boundary. Isolate CLI probes that write caches,
and label any skipped runtime check. Do not run `verify --smoke`.

## Inspect the changes not yet adopted

Resolve the installation's remote URL, defaulting to `origin`, and inspect
`refs/heads/main` even if the current branch tracks something else. Fetch it
into temporary storage as described in the reference. Record the remote name,
redacted URL, fetched SHA, and observation time. A cached `origin/main` is only
an offline fallback: explicitly report its freshness as unknown.

Import the installed HEAD into the temporary object database. Determine ancestry
and compare both `installed..target` commits and `installed` versus `target`
file contents. For divergence, inspect both sides from the merge base; commits
on remote `main` may have equivalent changes already adopted by cherry-pick.
Keep separate:

- incoming changes on `main`;
- commits and dirty files unique to the active checkout;
- machine drift from that checkout, including merges/copies not yet applied;
- settings intentionally owned by this machine.

Even with equal SHAs, check for unapplied configuration, old binaries, and stale
running consumers. Without shared history, do a content assessment and report
that automatic fast-forward adoption is unavailable.

A missing merge base usually means remote `main` was rewritten (for example to
remove private names), not that the histories are unrelated. Pair the two sides'
commits by author date and subject, and compare each pair's `git patch-id
--stable`; a pair whose patches differ shows what the rewrite changed. When every
installed commit has a twin, the adoption path is to reset onto the target after
saving dirty work, not to merge. Say so plainly: merging or pushing any ref from
the pre-rewrite history (branches, worktrees, backups) would restore what the
rewrite removed. List those refs, and which of them hold commits without a twin.

Trace relevant changes through the registry's tier/capability selection,
platform gates, dependencies, configure steps, config mappings, version pins,
AI merge/retirement logic, and runtime consumers. Compare affected settings
semantically against current values and last-applied records. Inspect the full
file when a patch alone hides ordering or precedence. Symlinked files change
as soon as the active checkout advances, before any apply.

Do not limit relevance to the profile: base configs always reconcile, and
tool-owned configs may apply to externally installed tools. Also flag newly
selected components introduced into the machine's existing tier or `ai=all`.
Explain why a change is applicable, already present, or outside this machine's
scope. Separate pre-existing problems from risks introduced by the target.

## Deliver an actionable assessment

Lead with a recommendation: ready to adopt, adopt after named prerequisites,
defer, or insufficient evidence. Include:

- **Baseline and confidence:** installation, profile/features, current and
  target SHAs, branch relationship, dirty state, remote freshness, checks made,
  and material unknowns.
- **Machine impact:** a compact table of affected component/file/setting,
  current state, target behavior, local interaction, and required action. Cite
  paths, keys, or commits without exposing private values.
- **Risks:** rank concrete findings high/medium/low, giving the trigger,
  consequence, evidence, and mitigation. Include relevant ownership conflicts,
  config retirement/overwrite, permissions, service/listener exposure, platform
  support, dependency/pin compatibility, and process restart requirements.
- **Upgrade path:** ordered, machine-specific commands for a later execution
  task, with prerequisites and stop conditions. Preserve the machine's tier,
  capabilities, opt-outs, and ownership choices. Separate checkout adoption,
  profile-based reconciliation, optional vendor/APT upgrades, and runtime
  restarts. Do not default to `--full`, `--force`, or `--upgrade`.
- **Verification and recovery:** post-upgrade checks and success criteria,
  explicit human actions, and a recovery plan tied to the actual artifacts.
  A Git rollback alone cannot restore replaced binaries, merged settings,
  package-manager changes, or services. Explain where backups exist and where
  rollback is unavailable or needs an operator.

Recommend `dotfiles update` only when the install-path checkout is clean,
attached to a suitable branch, and can fast-forward from its configured
upstream to the reviewed `main`. Otherwise explain the blocker and propose
preserving/reconciling local work before adoption; do not discard it or change
the upstream automatically. Require rechecking the remote SHA before execution
if `main` has moved since the assessment. End after the report; a review does
not authorize the upgrade.
