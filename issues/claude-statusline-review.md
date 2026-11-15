# Claude statusline: review the intent against current Claude Code behavior

**Status:** reviewed (2026-11-14); fixes proposed, not implemented. The review
is under [Review, 2026-11-14](#review-2026-11-14); the brief follows unchanged.

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

## Review, 2026-11-14

Claude Code 2.1.325, installed and latest published (`npm view`, top of the
[changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)).
No local mods were loaded; the user settings name the agent-badge plugin only.
Evidence is marked **D** (documented upstream), **O** (observed in a probe on
this machine), or **I** (inferred from code). The probes ran in throwaway
sessions: `claude --bg` and an isolated `tmux -L` server, a temporary mod
loaded with `--plugin-dir`, no prompts sent, every session stopped and removed.

### The finding that changes the design

The engine already resolves the compaction threshold and exposes it to mods.
`$.session.usage({ breakdown: "summary" })` returns `autoCompactThreshold`
(absent when off), `isAutoCompactEnabled`, `rawMaxTokens` (the compaction
window), `autocompactSource` and `model`. `summary` estimates locally and sends
no request (**D**: the mod API types shipped with 2.1.325). A probe mod logged
it at `session.start`. The 2.1.325 rows below are **O**:

| Launch | Engine threshold | Source | The renderer's marker |
| --- | --- | --- | --- |
| Opus 5.5 (1M), nothing set | 967,000 | model-default | 967,000 |
| `--autocompact 300k` | 267,000 | settings | 300,000 |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400k` | 367,000 | env | 400,000 |
| `--settings '{"autoCompactEnabled":false}'` | off | auto | 967,000, marker shown |
| `DISABLE_AUTO_COMPACT=1` | off | auto | hidden |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80` | 967,000 | model-default | 768,000 |
| `--autocompact 300k` with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` | 267,000 | settings | 150,000 |

So the threshold is the compaction window minus 33,000, at every window size
tested, and 967K on a native 1M model is the same rule. The renderer puts the
marker at the configured window itself, which is 33K late whenever a window is
set. This machine's `modelSettings.claude-fable-5-2.autoCompactWindow: 600000`
is drawn at 600K; by the same rule the engine compacts at 567K (**I**).

The percentage override is unresolved. The
[env-vars page](https://code.claude.com/docs/en/env-vars) says it sets "the
percentage (1-100) of the auto-compact window at which auto-compaction
triggers", and that it only lowers. The engine's figure ignored it at 80 and at
50, and the renderer applies a third formula (scaling the threshold percentage).
Filling a context to tell which figure is right was out of scope. Whatever the
answer, the statusline should show the engine's figure, which is also what
`/context` prints.

Recommendation: stop resolving configuration in the statusline. A small mod
publishes the engine's figures per session, and the renderer draws them or
draws no marker. That removes the settings scan, the `/proc` walk and the
environment parsing, about 60 lines, along with every finding below about
them.

### Findings, ranked

1. **The compaction marker comes from an incomplete second resolver** (**O**,
   all versions since `334671b`). Besides the 33K offset above:
   `autoCompactEnabled` is read from the user file only. The brief's
   reproduction holds: `false` in project settings leaves the marker. The key is
   honored in any file, user, project, local or managed
   ([settings reference](https://code.claude.com/docs/en/settings-reference#autocompactenabled), **D**).
   Managed settings, `--settings` and `--setting-sources` are not considered.
   `DISABLE_AUTO_COMPACT=true` is accepted, but only `1` is documented.
   `modelSettings` keys are matched by prefix, while upstream matches the
   canonical name plus alias, date suffix, `[1m]` and provider IDs (**D**,
   [model config](https://code.claude.com/docs/en/model-config)). Fix: the engine
   snapshot.
2. **Unknown is drawn as zero** (**O**). `used_percentage` is `null` early in a
   session (**D**, [statusline](https://code.claude.com/docs/en/statusline#available-data)),
   and `// 0` turns it into an empty bar and `0%`. Malformed or empty input does
   the same, with eight jq errors on stderr. Fix: draw `—` and no fill when the
   value is null or the input does not parse.
3. **The subagent fallback is unverified and mixes capacities.** The payload
   has no subagent identity. `agent.name` is only for `--agent` (**D**), and
   2.1.323 removed `subagentStatusLine`. Whether `transcript_path` points at a
   subagent transcript while one is open is neither documented nor observed;
   the brief's `STATUSLINE_DUMP` was added to find out. When the fallback does
   fire, it divides the subagent's tokens by the main session's window. It also
   slurps the last 200 lines; on a real transcript that was 612 KB, with single
   `api-request-blob` lines of about 90 KB (**O**). Fix: remove it, together
   with the model-name `sed` rewrite. Revisit only if a live dump shows the
   payload switching; then label the agent and show absolute tokens, not a
   percentage of a guessed window.
4. **Display strings reach the terminal raw** (**O**). A model `display_name`
   of `X\e]0;pwned\a\e[31m` sets the window title and colors the rest of the
   line, and a cwd containing `\e[2J` is printed as is. Gateway display names
   and directory names are not trusted input. Fix: strip C0 and C1 controls
   from the model and directory before printing.
5. **The deployed path ignores `CLAUDE_CONFIG_DIR`** (**I**).
   `lib/ai_preferences.py` installs `configs/ai/claude/` into
   `$CLAUDE_CONFIG_DIR` when it is set, but the command is
   `bash ~/.claude/statusline.sh`, and the renderer reads
   `$HOME/.claude/settings.json`. Fix: run
   `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"`. (**O**: this
   machine's `~/.claude/statusline.sh` is still the pre-`334671b` version;
   `ai-config` has not run since the merge.)
6. **Each refresh costs 65–80 ms** (**O**, ten runs in 0.67 s without a
   transcript and 0.80 s with one). That is eight or nine `jq` forks, three
   settings reads and a `/proc` walk. Updates are debounced at 300 ms, and an
   in-flight run is cancelled (**D**), so this is a cost, not a bug. Fix: one
   `jq` call that emits every field, plus one snapshot read.
7. **`STATUSLINE_DUMP` writes the payload under the default umask** (**I**): cwd,
   session id, transcript path and cost, to any path. Fix: remove it. It served
   the subagent question, which this review answers by dropping the fallback.
8. **Color tracks absolute fill, not the next action** (**I**). At 50/75/80%
   of a 1M window, a 600K compaction window compacts while the bar is still
   amber. Fix: when the threshold is known, color by fill relative to it.
9. **Narrow panes** (**I**). `COLUMNS` and `LINES` are set for the script
   (**D**), but a long directory label is never shortened. Fix: when the line
   would not fit in `COLUMNS`, shorten the directory label from the left, then
   drop the model.
10. **Accepted cost, unchanged**: a custom status line hides most footer
    keyboard hints, including `esc to interrupt` and `? for shortcuts` (**D**).
    Notifications share the row only outside fullscreen, and this machine runs
    `tui: fullscreen`.

Related harness fact (**O**): a `claude --bg` session runs with the daemon's
environment, not the launching shell's. In the probe, environment overrides set
on later `--bg` launches did not reach the session. The daemon kept the
environment of the shell that first started it. A statusline reading its own
environment still matches its session, but this is another reason to trust the
engine's figure.

### Decision table

| Signal | Source | Shown as | When unknown |
| --- | --- | --- | --- |
| Context fill | `context_window.used_percentage` (**D**: input, cache writes and cache reads over the full window) | bar and `NN%` | `—`, empty bar |
| Compaction point | engine snapshot `autoCompactThreshold` for the payload's `session_id`, used only when the snapshot's model matches `model.id` | bright `│` in the bar | no marker. Off: no marker and nothing else (decided 2026-11-14: minimal) |
| Bar color | fill relative to the threshold, or to the window without one | sage / amber / terra / red | relative to the window |
| Model | `model.display_name`, sanitized | dim text | omitted |
| Session or subagent | main session only | n/a | n/a |
| Directory | `workspace.current_dir` against `workspace.project_dir` | project-relative; `~`-relative and amber outside it | omitted |
| Effort, thinking, fast mode, prompt cache, session name, worktree | available (**D**) | omitted: the banner and footer already carry them, or they don't change a decision | n/a |
| Rate and spend limits | `rate_limits.*` (**D**, subscribers and gateways only) | optional: shown only at 80% or more | omitted |

### Proposed implementation

Defect fixes:

1. Add a snapshot mod: `register.ts` and a small writer script, in a new
   `plugins/claude-context/` plugin. It needs Claude Code 2.1.287 or newer,
   as agent-badge does. On `session.start`, `session.measure` (after every
   main-thread turn) and after `config.set`, it calls
   `$.session.usage({ breakdown: "summary" })`. It writes
   `{model, window, compactWindow, threshold|null, enabled, source, at}` to
   `${XDG_RUNTIME_DIR:-/tmp}/claude-statusline-$UID/<session id>.json`
   (directory 0700, file 0600), and removes the file at `session.end`. The
   writer and the renderer share that path rule, and a test holds them to it.
2. Rewrite the renderer around one `jq` call and that snapshot. Delete the
   settings scan, the `/proc` walk, the environment parsing, the subagent
   fallback and `STATUSLINE_DUMP`. Draw null as unknown, strip control
   characters, and keep exit status 0.
3. Change `statusLine.command` in `configs/claude-settings.json` to
   `bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"`.

Optional enhancements: threshold-relative color, `COLUMNS`-aware shortening,
headroom text (`threshold − total_input_tokens`, for example `↧320k`), and a
rate-limit segment at 80% or more.

Open product choices:

- **Where the mod lives.** A new plugin keeps the badge standalone, but needs
  install plumbing beside agent-badge. Adding a second module to
  `agent-badge-claude` needs no plumbing, but couples two concerns.
- ~~How "off" looks~~: decided 2026-11-14. Off draws no marker and adds
  nothing to the line.

### Tests to add

A new `tests/claude-statusline.sh` runs under a temporary HOME and
`XDG_RUNTIME_DIR`, with synthetic payloads and snapshots. It covers:

- With and without a snapshot, a snapshot that is off, and one for another
  model (unknown).
- A null or absent `used_percentage`, and malformed or empty input.
- Fill over 100%, and windows of 200K and 1M.
- Hostile model names and paths: the output must contain no ESC outside the
  palette's SGR codes.
- `CLAUDE_CONFIG_DIR`, and a `PATH` without `jq`.
- Exit status 0 every time, and a bound on running time.

For the mod, a `claude plugin test` case should seed `usage` and assert the
written file and its modes. Add both to CI with `bash -n` and ShellCheck.

Manual check, current Claude Code in tmux over SSH:

1. The marker sits where `/context` reports the auto-compact window, before
   and after `/autocompact 300k`.
2. `/config` Auto-compact off removes the marker.
3. `/model` to a model with a different window gives no marker until the next
   turn, then the right one.
4. A fresh session shows `—`.
5. A 60-column pane shortens the directory first.
