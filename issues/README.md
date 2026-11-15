# Issues

Design notes, plans and decisions, newest work first within each group. Each
note's own **Status** line is the authority; this index is updated with it.

## Open

- [Claude statusline review](claude-statusline-review.md): reviewed
  2026-11-14. The proposal: take the compaction threshold from the engine
  through a small mod, not a second settings resolver; drop the subagent
  fallback; fix the unknown, sanitizing and `CLAUDE_CONFIG_DIR` defects. Not
  implemented.
- [Agent badge for background sessions](agent-badge-background-sessions.md):
  `claude attach` and agent-view panes on a `--bg` session are badged and
  seeded. Implemented on branch `agent-badge-bg-viewers` (agent-badge 1.2.0);
  manual checks on the operator's tmux are open.
- [Agent parity](agent-parity.md): how far pi and OpenCode should follow Claude
  and Codex in review, last-reply, the badge and the compose editor.
- [Scheduled review on the desktop](scheduled-review-desktop.md): where the
  scheduled dependency review (`maintenance/dependency-review.md`) should run;
  nothing is set up.
- [Compose box](compose-agent-box.md): built for Claude, Codex and OpenCode; in
  testing.

## Implemented (kept as the record of what was decided)

- [Intent keys](intent-keys.md): one key per intent in every agent; the Defy's
  thumb keys are still to be set in Bazecor.
- [viz over SSH](viz-ssh-live-reload.md): private web viewer with live reload;
  part of its laptop checklist is still open.
- [Alt+I command drafting](ai-shell-command-widget.md).
- [Git profiles](git-profiles.md): not yet adopted on any machine.
- [Scrollback, copy, and compose](scrollback-copy-compose.md), with its
  [plan](scrollback-copy-compose-plan.md); absorbs
  [Codex review popup](codex-review-popup.md).
- Setup and update redesign: [status](setup-update-status.md),
  [design](setup-update-redesign.md), [plan](setup-update-plan.md),
  [review](setup-update-redesign-review.md).
- [AI settings per machine](ai-settings-per-machine.md).
- [Work tier sandbox boundary](work-tier-sandbox-boundary.md): decided.

## Parked

- [Compose AI cleanup](compose-ai-cleanup.md): could reuse Alt+I's model
  plumbing (`bin/ai-command`).
- [Moonlight and Sunshine](moonlight-sunshine.md): revisit after the xrdp layer.

## Not about dotfiles

- [Project toolkit name](project-toolkit-name.md): a spec sketch for a separate
  toolkit repository; kept here until that project has a home.
