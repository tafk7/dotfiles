# AI configuration ownership

`bin/ai-config` updates preferences without downloading or updating a CLI. The
native installers call it too. Run it from this checkout, or set `DOTFILES_DIR`
when invoking an installer through another path. Python 3.11+ is required.

| Source | Destination |
|---|---|
| `configs/codex.toml`, `codex.defaults.toml` | Declared keys in `~/.codex/config.toml` |
| `configs/claude-settings.json`, `.defaults.json` | Declared keys in `~/.claude/settings.json` |
| `configs/opencode.json` | Declared keys in `~/.config/opencode/opencode.json` |
| `configs/opencode-cli.json`, `.defaults.json` | Declared keys in `~/.config/opencode/cli.json`, once the V2 CLI is installed |
| `configs/ai/codex/` | Corresponding portable asset files under `~/.codex/` |
| `configs/ai/claude/` | Corresponding portable asset files under `~/.claude/` |

Each source holds two kinds of key, both in the user's own files, so this works
without root and touches no other user:

- Enforced keys (`codex.toml`, `claude-settings.json`, `opencode.json`,
  `opencode-cli.json`) are the same on every machine: telemetry and metrics
  off, no commit attribution, Claude's status line, opencode's sharing and
  update policy. Every apply puts them back, and verify reports a difference.
- Defaults (the `.defaults` siblings) are where each machine starts: model,
  effort, theme, key bindings, approval and sandbox policy. A default is
  written where the key is absent, and kept up to date with the repo while
  the machine still holds the value dotfiles last wrote. Once the machine
  changes or removes it, in the app or by hand, it is the machine's: never
  reverted, never reported. Moving a key from enforced to default hands it
  over with its current value.

The merge is recursive and lists count as single values; unlisted values
remain. Asset files listed in the source are owned as a whole; unlisted files
are never deleted. Account identity, project state, credentials,
plugin registrations, hook trust, and session histories are not portable assets.

Codex defaults to high reasoning. The model, provider, context window, and
compaction threshold depend on where requests are served, so they are left to
whatever configures the provider; named profiles can override any default.
Provider-specific Claude environment, such as gateway compatibility flags,
belongs to the provider configuration too, as do opencode's providers, models
and provider allowlist. Claude's effort level and auto-compaction are left to
each machine (set them in Claude Code; dotfiles neither sets nor checks
them). Nonessential traffic is
left to the machine: setting `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in
`~/.claude/settings.json` or a provider configuration also disables Claude's
automatic updater and makes `$.http.fetch` fail in Claude Code mods (use
`$.process.run` instead). opencode only notifies about
new releases and never shares sessions: its own updater reruns the upstream
installer without `--no-modify-path`, which would append to the repo-owned
`~/.bashrc`. Use `bin/ai-update claude`, `codex` or `opencode` to update
explicitly: it runs `setup.sh --CLI --only CLI --upgrade`, the official
installer's update path followed by the CLI's configure steps.

Settings and the agent-badge plugin are configure steps (`lib/configure.sh`),
not part of the installers: setup runs them after each selected AI CLI's
install step, whether it installed the CLI, found it current, or found an
external one, but not after a failed install. Registration adds this
repository as a marketplace and installs the plugin; a separate update step
brings an installed plugin to this checkout's version when its cache is stale
(`bin/ai-config claude --check-plugin`). OpenCode's settings are written only
for V2, so an external V1 keeps its own.

A portable key that leaves `configs/` is retired from each settings file by a
three-way comparison: `bin/ai-config` records the enforced leaves it applied
and the defaults it last wrote (in `~/.local/state/dotfiles/ai/`), and removes
one the sources no longer have only while the file still holds the value it
wrote; a table emptied by the removal goes too. A key edited since is kept and reported once, and the record
remembers it. Keys still in the overlay keep winning, lists count as single
values, and Pi's seed-once settings stay the user's. A key listed in
`configs/ai/released.json` is handed to the machine instead: dropped from the
record without touching its value, so a setting dotfiles stops managing keeps
whatever each machine has.

Before changes, files are copied into private, uniquely named subdirectories of
`~/.claude/backups`, `~/.codex/backups` or `~/.config/opencode/backups`. Alternate configuration homes use their
own `backups` subdirectory. A semantic no-op retains original bytes and creates no
backup. TOML formatting and comments normalize on a change; parsed values remain.
Invalid JSON/TOML, incompatible object shapes, and symlinked targets fail before
the planned configuration writes. Atomic replacement protects each file, but a
multi-file install is not a filesystem transaction: I/O failures can require a
rerun, with backups available for recovery.

Use `bin/ai-config --dry-run` before migration and `--check --plugins` afterward.
The native verifiers also run these checks for expected AI tools. Checks compare
enabled badge caches against the source manifest version and files; disabled
plugins are informational. After source changes, publish a new plugin version
and use `claude plugin update agent-badge@tafk7` or the Codex local-plugin
cachebuster/reinstall flow. Start new agent sessions after a plugin refresh.

Validation commands:

```sh
python3 tests/ai-config.py
bash tests/install-codex.sh
bash tests/install-ai.sh
```
