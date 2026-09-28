# AI configuration ownership

`bin/ai-config` updates preferences without downloading or updating a CLI. Both
native installers call it too. Run it from this checkout, or set `DOTFILES_DIR`
when invoking an installer through another path. Python 3.11+ is required.

| Source | Owned destination |
|---|---|
| `configs/codex.toml` | Declared keys in `~/.codex/config.toml` |
| `configs/claude-settings.json` | Declared keys in `~/.claude/settings.json` |
| `configs/ai/codex/` | Corresponding portable asset files under `~/.codex/` |
| `configs/ai/claude/` | Corresponding portable asset files under `~/.claude/` |

The merge is recursive: declared leaves win; unlisted values remain. Lists are
owned as a whole. Removing a key from the source stops managing it; it does not
delete a local value. Asset files listed in the source are owned as a whole;
unlisted files are never deleted. Account identity, project state, credentials,
plugin registrations, hook trust, and session histories are not portable assets.

Codex defaults to high reasoning. The model, provider, context window, and
compaction threshold depend on where requests are served, so they are left to
whatever configures the provider; named profiles can override any default.
Provider-specific Claude environment, such as gateway compatibility flags,
belongs to the provider configuration too. Claude retains medium effort and
disabled nonessential traffic. That
traffic setting disables automatic updates in the verified native version; use
`bin/ai-update claude` for explicit maintenance. This command uses the official
installer's existing `--force` update/repair path, including configuration and
plugin provisioning. `bin/ai-update codex` does the same for Codex.

Before changes, files are copied into private, uniquely named subdirectories of
`~/.claude/backups` or `~/.codex/backups`. Alternate configuration homes use their
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
