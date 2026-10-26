# Per-machine AI tool settings

Status: research back (2026-10-26); revised proposal below, waiting on the
open questions.

## Problem

`bin/ai-config` merges the portable keys in `configs/` into each tool's user
settings and puts them back on every apply; `dotfiles verify` reports any
difference as work for apply. The tools write in-app changes (model picker,
effort, `/config` toggles) to those same files, so a preference changed in the
app is reverted on the next apply and reported until then. Some keys should be
the same everywhere (telemetry off, no commit attribution, key bindings that
leave Alt to tmux); others are only starting points a machine should own.

## Findings

- Codex rewrote `~/.codex/config.toml` at 21:09 on 2026-10-26, after an apply
  found it current: an older copy of the file with `model_reasoning_effort =
  "xhigh"`. The writer was most likely Codex's app-server daemon (started
  2026-10-25, outside tmux, so a tmux restart does not stop it; its log shows
  sessions closing at 21:06 and 21:08). New Codex sessions attach to that
  daemon, so restarting Codex in a pane does not reload its config;
  `codex app-server daemon stop` or `restart` does.
- Launch flags (`CLAUDE_FLAGS`, `CODEX_FLAGS`, `OPENCODE_FLAGS` in
  `~/.shell.local`) reach only sessions started from a shell, not editor
  extensions or the Codex daemon.
- The sandbox kit delivers Claude's portable keys as managed settings
  (`kits/sync-portable.py`), which a sandbox session cannot override.
- `dotfiles verify` checks Claude's and Codex's settings but not OpenCode's;
  apply reconciles all three.
- Pi's settings are seeded only when the file is absent; this machine's
  predates that, so Pi's install telemetry is still on here.

## Done

- `9cfa425`: Claude's `effortLevel` and `autoCompactEnabled` left management.
  Keys listed in `configs/ai/released.json` are dropped from the record with
  their values left in place, instead of retired.

## Options

| Option | In-app change sticks | verify stays meaningful | Per-machine upkeep |
|---|---|---|---|
| Machine-local override file per tool | No, until mirrored there | Yes | A file per tool |
| Per-machine list of keys not to manage | For listed keys | Yes | A list |
| Enforced and initial keys in the repo | For every preference | Yes | None |
| Release the key entirely | Yes | Yes | None |
| Launch flags | Shell-started sessions only | Yes | Flags |

## Research (2026-10-26)

A research agent's report. The layer paths are confirmed present in the
installed binaries (Claude Code 2.1.311, Codex 0.164.0, OpenCode 2.0.28,
Pi 0.85.1); precedence is as documented, not tested here.

- Claude Code reads managed settings from `/etc/claude-code/managed-settings.json`
  and `managed-settings.d/*.json`, above the user file and never written by
  the tool. Managed keys are locked, except `model`, documented as a starting
  default. An organization's managed source (server or MDM) wins over the
  file under the default `"first-wins"`.
- Codex reads `/etc/codex/config.toml` below `~/.codex/config.toml`: a
  defaults layer the user's choices override. `/etc/codex/requirements.toml`
  constrains security keys (approval, sandbox, network); the legacy
  `/etc/codex/managed_config.toml` overrides user config and `-c` at start.
  The app-server rewrites the whole user TOML; `-c` sessions bypass the
  shared daemon.
- OpenCode reads `/etc/opencode`: lowest precedence on 2.0.28, highest
  (enforced) from 2.0.29, per its changelog. `OPENCODE_CLI_CONFIG_CONTENT`
  overlays `cli.json` and is never written.
- Pi has no system layer; `PI_TELEMETRY=0` in the environment overrides
  `enableInstallTelemetry`.
- Organizations enforce security, telemetry, and compliance keys and leave
  model, effort, and UI as defaults. Dotfiles managers that merge into
  app-written files (chezmoi `modify_`, home-manager's proposed merger) meet
  the same needs: a last-applied record for removals, byte-preserving output.

## Revised proposal

Enforced keys go to a layer the tool reads and never writes. Defaults go to a
lower layer where one exists; otherwise into the user file, tracked by the
value dotfiles last wrote: updated while the machine still holds it, the
machine's once changed. Keys leaving the user file are retired by the existing
three-way record, so a machine's own changes (Codex's `xhigh`) stay and win.

| | Enforced | Defaults |
|---|---|---|
| Claude | `managed-settings.d/50-dotfiles.json`: attribution off, telemetry and error reporting off, the status line; `model` (a managed default) | user file, tracked: theme, `tui`, tool search, the warning skips |
| Codex | `requirements.toml` for approval and sandbox, if enforced | `/etc/codex/config.toml`: reasoning efforts, history, status line, key bindings, `otel` |
| OpenCode | `/etc/opencode` on 2.0.29 or later: `share`, `update` | `cli.json`, tracked: key bindings |
| Pi | `PI_TELEMETRY=0` in `shell/env.sh` | user file, tracked: `enableInstallTelemetry` |

The system files need sudo and affect every user of the host; without sudo,
or below a version gate, enforced keys stay in the user file as today.
dotfiles stops writing `~/.codex/config.toml` at all, which ends the fights
with Codex's daemon.

## Open questions

- Sudo-written system files for AI settings on dev and work machines, with
  today's behavior as the fallback: acceptable?
- Codex's approval policy and sandbox mode: defaults, or enforced through
  `requirements.toml`? Codex's `otel`: a default, or enforced through the
  legacy `managed_config.toml`?
- The research recommends a per-machine overlay now. With defaults owned by
  each machine once changed, it would only declare a machine's values from
  dotfiles; deferred unless an enforced key must differ on one machine.
- An organization's managed settings would silently replace the Claude file
  layer. The `ai` capability is meant to stay off on organization-managed
  machines, and verify cannot see the effective settings.
- This machine, meanwhile: Codex's `xhigh` is kept by hand, so verify reports
  `codex settings` until this lands. Pi's telemetry can be turned off by hand
  (`"enableInstallTelemetry": false` in `~/.pi/agent/settings.json`).

## Research brief

Given to a research agent on 2026-10-26.

> Distributing default settings for AI coding CLIs across machines.
>
> Context: a personal dotfiles repository configures Claude Code (2.1.310),
> OpenAI Codex CLI (0.164.0), OpenCode (2.0.28, V2) and Pi (0.85.1) on several
> Linux machines and Docker-based sandboxes. A script merges "portable" keys
> into each tool's user settings file, re-applies them every run, reports
> drift, and retires keys removed from the repo. The tools write in-app
> changes to the same files, so preferences changed in the app are reverted;
> Codex's app-server daemon appears to write `config.toml` back from memory.
> The proposal: enforced keys, initial keys (written once, then the
> machine's), a hand-over list, no per-machine override file yet. Claude
> settings reach sandboxes as managed settings.
>
> Questions: (1) Each tool's settings layers and precedence (managed, system,
> user, project, local, environment, flags, profiles, remote config): is there
> an overridable defaults layer, where do in-app changes go, does the tool
> rewrite config it didn't change, and do Codex's `-c` and `--profile` reach
> daemon-served sessions? (2) How organizations distribute AI coding tool
> defaults and decide enforced versus default. (3) How dotfiles managers
> (chezmoi `create_`/`modify_`, home-manager, yadm, VS Code settings
> practice) handle files the application also writes. (4) Pitfalls: tools
> overwriting managed files, daemons holding stale config, round-trip
> formatting, schema changes, secrets and machine paths in settings.
>
> Deliverable: a table per tool (layers, precedence, where in-app changes go,
> defaults layer, enterprise specifics, doc version or date); how
> organizations and dotfiles managers split enforced from default; an
> assessment of the proposal with native alternatives and risks; primary
> sources for every claim, with inferred or version-dependent points marked.
