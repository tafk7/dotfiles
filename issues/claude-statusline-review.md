# Claude statusline: review the intent against current Claude Code behavior

**Status:** open (2026-11-14). Research and review brief for another agent;
implementation decisions are still open.

## Goal and intent

Review the whole statusline against the latest Claude Code features and known
pitfalls, then propose the simplest design that serves the operator's needs.
Go beyond the settings discrepancy below; do not assume the current approach
or every new upstream field deserves to survive.

The current design implies these priorities; validate them against the repo
and make any proposed change of intent explicit:

- Show context consumption and useful headroom at a glance, with a compaction
  marker only when its meaning is supported. Distinguish unknown from zero,
  and an estimate from an authoritative threshold.
- Identify the model and the session or subagent the numbers actually describe.
- Show the live working directory relative to the project, with an obvious
  warning when the session has moved outside it.
- Stay compact, readable, and fast in tmux over SSH through WezTerm, including
  narrow panes. Avoid duplicating information already supplied by the footer
  or agent badge unless it helps an operator make a decision.
- Reflect the machine's and provider's effective choices. Dotfiles deliberately
  released ownership of `autoCompactEnabled` and effort; this review must not
  re-enforce them or change provider configuration to make the display work.

## Starting point

The 2026-11-14 reconciliation merged local `94d3614` with remote `a341f1a`
in `70e496b`. Remote introduced the current statusline in `334671b`.

Read these together:

- [Renderer](../configs/ai/claude/statusline.sh).
- [Enforced settings](../configs/claude-settings.json),
  [machine defaults](../configs/claude-settings.defaults.json), and
  [released settings](../configs/ai/released.json).
- [Configuration ownership](../docs/ai-configuration.md) and the
  [per-machine settings decision](ai-settings-per-machine.md).
- [Configuration reconciliation](../lib/ai_preferences.py),
  [configuration tests](../tests/ai-config.py), and
  [portable sandbox kit generation](../kits/sync-portable.py).
- [Background-session badge issue](agent-badge-background-sessions.md), for
  related session-identity pitfalls; fixing the badge is a separate task.

The renderer now adds an autocompact marker, reads a subagent transcript as a
fallback, and removes the earlier output-token label. Its comments and
hard-coded thresholds are hypotheses to verify, not upstream specifications.

## Initial observation to reproduce and qualify

With an isolated temporary HOME and project, send the renderer a payload with
40% usage, a 1,000,000-token window, a model id, and both workspace directories
set to that project. Setting `autoCompactEnabled` to `false` in the user
`~/.claude/settings.json` hides the marker. Setting it only in the project's
`.claude/settings.json` leaves the marker visible. The script checks the user
file for that boolean but reads several files for `autoCompactWindow`.

This establishes the renderer's behavior, **not** that Claude Code honors that
key in both scopes. First verify the current setting's supported storage,
scope, precedence, and effect in Claude Code. It may require correcting our
assumption rather than extending the renderer's file scan. Include project
local overrides and a higher-precedence `true` overriding a lower `false` in
the investigation where those scopes are supported.

## Review scope

1. **Establish the version and evidence.** Record the review date, installed
   Claude Code version, latest published release, and relevant intervening
   changes. Distinguish stock Claude Code from any local mods or gateway
   extensions; classify each dependency as documented, observed, or inferred.
   Use primary documentation, release notes, and small reproducible probes.
   Re-check upstream at pickup time; these links are starting points, not a
   frozen compatibility contract.

2. **Check the payload contract and useful native features.** Verify the
   meaning and freshness of input, cache, output, and percentage fields;
   behavior before the first response, after compaction, and during model
   changes; and how actual window capacity is reported. Assess whether native
   effort, thinking, fast-mode, session/worktree identity, rate/spend limits,
   or prompt-cache data improves the intended display. Recommend only signals
   that earn their space and handle unavailable fields without fabricated data.

3. **Determine effective configuration rather than approximating it blindly.**
   Trace supported config homes, global preferences, user/project/local and
   managed sources, settings-source selection, launch flags or inline settings,
   environment, in-app changes, directory changes, and worktrees. Confirm the
   actual semantics of `autoCompactEnabled`, `autoCompactWindow`,
   `modelSettings`, `--autocompact`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`,
   `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `DISABLE_AUTO_COMPACT`, and
   `DISABLE_COMPACT` for the relevant versions and providers. Unsupported or
   mod-only names should be labeled or removed. Decide which effective values
   the statusline can know reliably; prefer an explicit unknown state to a
   second, incomplete configuration resolver.

4. **Audit compaction and context math.** Check threshold units and suffixes,
   percentage-override semantics, reserved headroom, the 100k floor, 967k
   default, window-minus-33k estimate, and 20-cell rounding/clamping. Cover
   different model windows and provider-reported capacities without treating
   model names as authoritative. Decide whether absolute fill, headroom to
   compaction, or both best communicate the operator's next action. Validate
   disabled/manual compaction and changes made during a session.

5. **Audit main-session and subagent attribution.** Verify which session the
   payload describes when a subagent transcript is open, and what current
   native fields expose. Test the `/subagents/` path assumption, last-200-line
   scan, partial JSONL records, tool-only tails, missing usage, resumed or
   background/attached sessions, and different model windows. Do not combine
   one agent's tokens with another's capacity silently. Prefer supported
   payload data; document any unavoidable transcript fallback and its limits.

6. **Review runtime and rendering pitfalls.** Check update scheduling,
   cancellation, latency from repeated `jq`/settings/transcript reads, and the
   four-ancestor `/proc` command-line heuristic. Exercise absent or malformed
   JSON, numeric edge cases, missing `jq`, unreadable files, and no workspace.
   Check ANSI/control-character handling in model names and paths, long or
   Unicode paths, narrow panes, and the script's exit status. Check the
   privacy and permissions of `STATUSLINE_DUMP`. Keep statusline refreshes
   bounded and local; do not add network calls, credential reads, or global
   transcript searches. Any cache must isolate concurrent sessions.

7. **Check integration and ownership.** Confirm deployment through `ai-config`,
   alternate config directories, and sandbox kits. Compare the custom display
   with today's built-in footer and statusline settings, including loss of
   keyboard hints or rows used by notifications. Describe any native feature
   that can replace custom logic, and any compatibility cost of using it.

## Upstream starting points

- [Statusline contract and troubleshooting](https://code.claude.com/docs/en/statusline).
- [Settings files and precedence](https://code.claude.com/docs/en/settings).
- [Official changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md).

A preliminary check on 2026-11-14 found native effort, thinking, fast-mode,
session/worktree, rate/spend-limit, and prompt-cache fields in the
[statusline reference](https://code.claude.com/docs/en/statusline#available-data).
It also documents nullable context fields, input-only `used_percentage`,
terminal dimensions via `COLUMNS`/`LINES`, and custom-statusline effects on
footer hints. Treat these as review leads; confirm availability and semantics
for the versions and providers actually used.

## Deliverable and acceptance

- A dated, source-linked review in this issue: current intent, actual behavior,
  ranked findings, and a proposed display. For every dependency or finding,
  record affected versions/providers, evidence, confidence, and fallback.
- A decision table mapping each intended signal to its best supported source,
  display semantics, and behavior when unknown. Explain what to keep, replace
  with native functionality, simplify, or omit; do not expand the UI merely
  because fields exist.
- A minimal implementation plan with resolved defects separated from optional
  enhancements. Do not silently change machine-owned preferences or publish
  captured session data. Any unresolved product choice should be explicit.
- Meaningful fixture-based regression tests for supported settings precedence,
  enabled/disabled/unknown compaction, threshold calculations, missing/null
  payloads, model/window changes, subagent attribution, hostile display strings,
  and bounded behavior. Add them to CI if implemented. Use temporary HOME/XDG
  roots and sanitized synthetic fixtures; tests must not call a model or touch
  the operator's settings, live tmux server, or real transcripts.
- Bash syntax and ShellCheck checks, configuration/deployment checks where
  affected, and a short manual checklist for current Claude Code in tmux over
  SSH. Distinguish automated evidence from behavior still awaiting a live check.
- Update this issue's status and [the index](README.md) when the review or
  implementation lands. A completed research report is distinct from an
  implemented and validated renderer.
