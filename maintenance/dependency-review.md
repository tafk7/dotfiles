# Scheduled dependency review

The prompt for the scheduled Claude job that keeps this repository's pins
current. It runs against the GitHub repository in one of two modes, named in
the schedule: `monthly` (the review) and `weekly` (the security check). The
judgment is the agent's, the digests and checks are tested code
(`dotfiles bump`, `check-updates`), and the merge is the owner's.

## Rules for both modes

- Work on a new branch from `main`, named `deps/YYYY-MM-DD` (monthly) or
  `security/YYYY-MM-DD` (weekly). Never push to `main`, never merge, never
  force-push.
- Move pins only with `bin/dotfiles bump TOOL [VERSION]`; never edit
  `versions.lock`, `eget.toml` tags, or `configs/init.vim` commits by hand.
  Bump checks both architectures through each source's own trust and refuses
  a release younger than 14 days. Use `--security` only for a release that
  fixes an advisory affecting the currently pinned version, and say so.
- One commit per tool, with any configuration that release needs (renamed
  tmux options, deprecated Neovim settings, changed CLI flags in `shell/` or
  `bin/`) in the same commit. Each commit message has an imperative subject
  and a body that says what changed and why.
- Run the suite before opening the pull request (`tests/*.sh`, then the
  Python tests CI runs). A failure caused by the bump is fixed in that tool's
  commit, or the bump is dropped and listed as skipped with the failure.
- An sbx bump is marked "needs kit validation" in the pull request: the kits
  (`kits/`) must be built with the new version before merging, and their
  headers updated in the same pull request when a workaround changes.
- Open one pull request, or none when nothing qualifies. Its description has a
  rationale per bump (what changed upstream, why it is safe or needed, what
  config moved with it), and a list of what was not bumped and why.

## Monthly mode

1. Gather: run `bin/check-updates --outdated --json`. It lists every pin that
   is behind, with advisories published since the pinned release.
2. Read the release notes, changelogs, and security advisories for each
   candidate, and for the unpinned apt-repository tools (Docker, Tailscale,
   Google Cloud CLI, Azure CLI), which `dotfiles update --upgrade` moves.
3. Judge each candidate: breaking changes, configuration this repository must
   adjust, security relevance, and the cool-down. Prefer the newest release
   outside the cool-down; skip one with an unresolved regression that affects
   how this repository uses the tool.
4. Apply with `bin/dotfiles bump`, adjust configuration, run the suite.
5. Open the pull request. Under "Not bumped", list each candidate left alone
   and why, and notable changes in the unpinned tools.

## Weekly mode

1. Run `bin/check-updates --json` and keep only pins with advisories.
2. For each advisory, decide whether it affects the pinned version and how
   this repository uses the tool. Stop if none does: no branch, no pull
   request.
3. Bump each affected pin to the release that fixes it, with `--security`
   when that release is inside the cool-down, and say so in the commit and
   the pull request.
4. Run the suite and open a pull request titled with the advisory IDs.
