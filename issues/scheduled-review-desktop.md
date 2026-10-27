# Scheduled dependency review from the Claude desktop app

Status: open (2026-10-27). To look into; nothing is set up.

## Goal

Run `maintenance/dependency-review.md` on a schedule: `monthly` (the review)
and `weekly` (the security check). Each run works on a new branch and opens
at most one pull request for the owner to merge. This is the end of plan step
4.3, whose acceptance is one manual run on a branch that produces a
reviewable pull request; the schedule follows.

## Where things are

- The prompt is checked in, and `main` on GitHub has everything it uses
  (`dotfiles bump`, `check-updates --outdated --json`, the suite), as of
  2026-10-27.
- The plan assumed a scheduled Claude Code job in the cloud against the GitHub
  repository. The question here is whether a scheduled task in the Claude
  desktop app is the better home.

## Questions

- What a desktop scheduled task runs: Claude Code with a shell, git, and `gh`,
  or something narrower. The job needs `bin/dotfiles bump`,
  `bin/check-updates`, the test suite, a push of its branch, and
  `gh pr create`.
- Where it runs. The desktop app runs on macOS and Windows, but the suite
  assumes Ubuntu (dpkg-query, GNU tools, tmux, systemd), and this machine is a
  Linux VM. Does the task run locally (in WSL on Windows?), reach this host
  over SSH, or run in the cloud?
- What happens to a run when the computer is asleep or the app is closed:
  skipped, delayed, or caught up.
- Credentials: how the task gets GitHub access limited to this repository
  (push a branch, open a pull request; no merge, no push to `main`).
- Permissions: whether the task's tool permissions can be pinned so the
  prompt's rules (never push to `main`, never merge, never force-push) are
  enforced, not only asked for.
- How the mode (`monthly` or `weekly`) reaches the prompt, and how a failed or
  empty run is reported.

## Alternatives

- A Claude Code routine in the cloud (`/schedule`): no dependence on a
  computer being on; the same questions about its environment and GitHub
  access apply.
- cron or a systemd timer on this host running `claude -p`: the suite's own
  OS, but the job holds this machine's credentials.

## Done when

One manual run on a branch produces a reviewable pull request, then both
modes are scheduled, each with the user's confirmation at that time.
