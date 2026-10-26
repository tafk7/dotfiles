# Per-machine AI tool settings

Status: on hold while research runs (2026-10-26); the research brief is below.

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

## Proposal (pending the research)

Two kinds of portable key. Enforced keys behave as today. Initial keys are
written once per machine, recorded, and from then on the machine's: changed or
deleted, they stay that way, and verify ignores them. Moving a key from
enforced to initial hands it over without changing its value. The sandbox kit
would enforce only enforced keys. Defer the per-machine override file until an
enforced key must differ on one machine.

| | Enforced | Initial |
|---|---|---|
| Claude | attribution off; telemetry and error reporting off; the status line (runs dotfiles' script) | model, theme, `tui`, tool search, the two warning skips |
| Codex | `otel` off; key bindings | reasoning efforts, approval policy and reviewer, sandbox mode, history, status line |
| OpenCode | `share` disabled; `update` notify (its updater edits `~/.bashrc`) | key bindings |
| Pi | | install telemetry off (seeded once per key, not only when the file is absent) |

## Open questions

- Codex's approval policy and sandbox mode: may a machine loosen them
  silently (initial), or are they enforced?
- Does the rest of the split hold?
- Would a native layer do better than editing the user file: a defaults tier
  in Claude Code's settings hierarchy, Codex's administrator configuration,
  OpenCode's remote or custom config?
- This machine, meanwhile: Codex's `xhigh` is kept by hand, so verify reports
  `codex settings` until this is decided. Pi's telemetry can be turned off
  by hand (`"enableInstallTelemetry": false` in `~/.pi/agent/settings.json`).

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
