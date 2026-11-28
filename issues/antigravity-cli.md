# Antigravity's terminal CLI (`agy`) as an opt-in AI tool

**Status:** open, partly built (2026-11-28). The design rests on research and
hands-on checks of `agy` 1.5.14 (2026-11-22), against dotfiles `2bb6126`;
paths below were rechecked at `8da3082`.

Built: `installers/install-antigravity.sh` (manifest, SHA-512, no vendor
script; a real install of 1.5.18 checked), `verify_sha512`, the registry row
(an optional AI CLI: `--antigravity`, never `--ai` or `--full`),
`bin/ai-update`, `dotfiles upgrade`, staleness, `shell/tools/antigravity.sh`
(refuses `agy update` and `agy install`), `AGY_CLI_DISABLE_AUTO_UPDATE=true`
in `shell/env.sh`, the `ai-config` merge (`configs/antigravity-cli.json`:
`showFeedbackSurvey: false`; defaults `altScreenMode: "never"` and Claude's
`agent-trust` deny rule; `toolPermission` is left at the CLI's default,
`request-review`), docs, and `tests/install-antigravity.sh` and
`tests/ai-config.py`. The wrapper does not add `$AGY_FLAGS`: flags before a
subcommand (`acp`, `models`) could break it.

Still open: tmux and keys (the agent regex, keymap, compose, review,
last-reply, the badge), the container scenarios and the chat fake, kits, and
the questions under [Open](#open).

The installer also coexists with a machine's launcher earlier on PATH:
install, upgrade, observation, verification and ledger recording use
`~/.local/bin/agy`, while interactive calls keep the launcher in front.
The installer saves the caller's PATH before dotfiles adds its own tools and
keeps that snapshot only within the capturing process's live tree, including
re-execs and child installers. It reads the candidate file without running
it. A launcher must be a readable script starting with `#!` and contain the
exact line
`# dotfiles-launcher: agy` within its first ten lines. This declares that it
sets up the environment and defers to `~/.local/bin/agy`. It is accepted when
earlier on that PATH or when the managed directory is not on PATH yet; a
script after the managed directory is refused to avoid shadowing it.
Creating or forcibly reinstalling a copy refuses unmarked scripts and
separate ELF executables, including the vendor's compiled binary: dotfiles
does not install a hidden second copy behind them. Unknown or unreadable
files are preserved too; the refusal explains the launcher declaration.
A working managed copy is kept or upgraded by absolute path even with an
unmarked script or ELF earlier on PATH, so upgrades do not depend on when
the launcher adds its marker. An alias of the managed file is the same copy
and can be upgraded. The rule needs no working launcher environment or
version response; installing other tools preserves existing PATH order.

## User need

Google Antigravity is a family of agent tools: a desktop App, an IDE (a VS Code
fork), IDE extensions, an SDK and a terminal CLI, `agy`. The goal is `agy`
installed and configured by dotfiles the way Claude, Codex, OpenCode and pi
are: from `setup.sh`, upgraded by `dotfiles upgrade`, with settings merged by
`ai-config`, usable over ssh and tmux.

Decided so far:

- **The CLI only.** The App and the IDE are out of scope.
- **Opt-in.** `--antigravity` installs it; `--ai` and `--full` do not.
- **Neutral.** The same install serves a personal machine signed in to Google
  or a machine that routes `agy` to a custom model gateway. dotfiles sets no
  gateway, account, model or provider. A machine's own setup, outside dotfiles,
  does that (see [Accounts and gateways](#accounts-and-gateways)).

## The tool (agy 1.5.14)

- **One static binary.** The release is a tarball (about 100 MB) holding one
  member, `antigravity`, a static Go binary (about 270 MB), installed as
  `~/.local/bin/agy`. It runs from there with no further install step. The
  process name is `agy`, so tmux's `#{pane_current_command}` shows `agy`.
- **Surfaces:** a full-screen TUI suited to ssh and tmux (`altScreenMode:
  "never"` keeps tmux scrollback); headless `agy -p` with `--output-format
  stream-json` and `--input-format stream-json`; `agy acp`, an Agent Client
  Protocol server.
- **The vendor installer** (`curl -fsSL https://antigravity.google/cli/install.sh | bash`):
  1. reads a per-platform manifest JSON (on a Cloud Run host) holding
     `version`, `url` and `sha512`;
  2. downloads the tarball from Google Cloud Storage and checks the sha512;
  3. runs `agy install`, which **edits the shell profile** (PATH and aliases;
     `--skip-path`, `--skip-aliases` turn each off).
- **Integrity:** a sha512 in a manifest served over HTTPS. No detached
  signature, no GPG or Sigstore. Only the current version is discoverable;
  older tarballs sit at build-numbered paths, so a recorded URL should keep
  working (not yet checked).
- **Self-update:** the CLI checks the manifest at every start and updates
  itself. `AGY_CLI_DISABLE_AUTO_UPDATE=true` stops that check (no fetch, no
  `updater/` files). **An explicit `agy update` ignores it** and fetches anyway.
- **Settings:** `~/.gemini/antigravity-cli/settings.json` (schema:
  `https://antigravity.google/schemas/v1/settings.json`). **The CLI rewrites
  this file itself** at mode 0600, keeping unknown keys, so it must be merged
  into, never symlinked. On a first run it holds only `trustedWorkspaces`.
  Keys of interest: `altScreenMode`, `toolPermission`,
  `permissions.{allow,ask,deny}`, `enableTerminalSandbox`,
  `showFeedbackSurvey`, `model`, `modelProvider`, `customModelsConfig`. It has
  no gateway, update or plugin keys. `~/.antigravity/settings.json` is not read
  by the CLI.
- **Other files under `~/.gemini/`:** `antigravity-cli/bin/agentapi`,
  `config/config.json`, `config/mcp_config.json` (MCP), `config/hooks.json`,
  `skills/`, an onboarding cache, `installation_id`, logs and conversation
  stores. Rules: `~/.gemini/AGENTS.md` and `~/.gemini/GEMINI.md` globally;
  `AGENTS.md`, `GEMINI.md` and `.agents/rules/` per workspace. **`~/.gemini` is
  shared with Gemini CLI**, so removal must never take the whole directory.
- **Admin settings:** `/etc/antigravity/admin_settings.json` (root) can lock
  sign-in, the gateway, models, the plugin marketplace and permission ceilings,
  and **overrides the user's environment**. Out of dotfiles' scope (sudo).
- **Sign-in and keyring:** a Google sign-in over ssh is a manual URL loop
  (open the printed URL locally, paste the code back). Credentials go to the
  OS keyring over D-Bus Secret Service, so headless sign-in needs
  `dbus-launch` and a keyring daemon. Gateway mode needs neither.
- **Terminal sandbox:** uses unprivileged user namespaces. On Ubuntu 24.04 with
  `kernel.apparmor_restrict_unprivileged_userns = 1` the CLI hides the sandbox
  options, so the permission preset carries more weight there.
- **Proxies:** its HTTP clients honour `HTTPS_PROXY`, `HTTP_PROXY` and
  `NO_PROXY`. `.env` files are not loaded; `GOOGLE_API_KEY` is ignored.
- **Licence:** proprietary, under Google's terms. Personal Google accounts on
  any plan; Workspace accounts only on Pay As You Go or Gemini Enterprise.

### Network contacts (measured offline, agy 1.5.14)

| Destination | What | When |
|---|---|---|
| the updater manifest host (Cloud Run) | update check | every start, unless `AGY_CLI_DISABLE_AUTO_UPDATE=true`; always on `agy update` |
| `play.googleapis.com` | Clearcut telemetry | signed-in or unconfigured runs only (over 100 posts in 5 min idle); none in gateway mode |
| `accounts.google.com`, `oauth2.googleapis.com` | sign-in | without a gateway |
| `www.gstatic.com` | plugin marketplace | TUI start; closed only by admin settings or a proxy |
| `raw.githubusercontent.com` | release notes | `agy changelog` only |
| `storage.googleapis.com` | the tarball | install and upgrade only |
| the model provider or gateway | model calls (`search_web` is a second chat request) | every prompt |

Telemetry is an **account** setting ("always off for business accounts"); no
file key or variable switches it off. `--version` and `--help` contact nothing.

### Accounts and gateways

`agy` reaches models one of three ways: a Google sign-in, a Gemini API key
(`modelProvider: "gemini"` with `GEMINI_API_KEY`) or Vertex ADC
(`AGY_ADC_AUTH=true`), or a **custom gateway** through `AGY_LLM_GATEWAY_*`
(documented for enterprise gateways; works with any compatible one, with no
Google account):

| Variable | Meaning |
|---|---|
| `AGY_LLM_GATEWAY_URL` | base URL; https except for localhost |
| `AGY_LLM_GATEWAY_API_KEY` | sent as `Authorization: Bearer` |
| `AGY_LLM_GATEWAY_WIRE_PROTOCOL` | `genai` (default) or `openai`; `agy acp` supports `genai` only |
| `AGY_LLM_GATEWAY_MODELS` | comma list, no spaces |
| `AGY_LLM_GATEWAY_HEADERS` | extra headers, split on commas and newlines |
| `AGY_LLM_GATEWAY_CA_CERT`, `AGY_LLM_GATEWAY_PROXY_URL` | a private CA, an egress proxy |

Observed behaviour that differs from the documentation:

- `openai` posts to `{URL}/chat/completions`, not `{URL}/v1/chat/completions`,
  so the URL normally ends in `/v1`. `genai` posts to
  `{URL}/v1beta/models/MODEL:streamGenerateContent?alt=sse` and reads SSE only.
- No telemetry and no model discovery in gateway mode; `agy models` lists
  `AGY_LLM_GATEWAY_MODELS` without a request.
- **A streamed tool call must end with `finish_reason: "tool_calls"`.** One
  ending in `"stop"` is discarded ("model output must contain either output
  text or tool calls"); agy retries, then exits 0 with no answer. Some
  OpenAI-compatible gateways send `"stop"`; a small relay that rewrites that
  one field fixes it.
- Errors (401, 400, 404, unreachable) exit 3 with a message; nothing falls back
  to Google.
- An unset gateway means sign-in and telemetry. A machine that must use only a
  gateway needs that enforced outside dotfiles (a launcher earlier on PATH,
  admin settings, a proxy). dotfiles' part is to not undercut it: call `agy`
  through PATH for interactive use, never run `agy update` or `agy install`,
  never write gateway or model keys. Management probes use the managed
  binary's absolute path with its auto-update check disabled.

## Proposed design

The pattern to copy is codex and pi.

**Install**

- `installers/install-antigravity.sh`, new, the usual shape: `lib/install.sh`,
  `--observe` through `observe_component antigravity`, `--force`, `--update`;
  when creating or forcibly reinstalling, refuse separate installs and
  launchers after the managed directory (exit 2); keep an earlier declared
  launcher in front, retain or upgrade a working managed copy,
  verify by absolute path (`~/.local/bin/agy --version`).
- **Read the manifest directly; skip the vendor script.** Fetch the manifest
  JSON, download `url`, check `sha512`, extract `antigravity` into a temporary
  directory and install it atomically as `~/.local/bin/agy`. No vendor script
  runs and the profile is never touched. An upgrade is the same fetch.
- Never run `agy install` or `agy update` from the installer, `--update` or
  `dotfiles upgrade`.
- `lib/install.sh`: add `verify_sha512` beside `verify_sha256`.
- Test seam: `DOTFILES_ANTIGRAVITY_MANIFEST_URL` (may be `file://`), in the
  manner of `DOTFILES_CODEX_INSTALLER_SCRIPT`. A machine that must not fetch
  from Google points it at a mirror.
- Pinning: a moving version by default (as claude and codex). A
  `versions.lock` pin only if a release breaks something; the lock is sha256
  only, so either record a sha256 cross-checked against the manifest's sha512
  or add a sha512 column (and change `tests/versions-lock.sh`).

**Registry and setup**

- `lib/registry.sh`: the tool row (`antigravity agy installer - ai …`), policy
  `vendor`, an update contract (`moving-vendor-installer` or a new
  `moving-vendor-manifest`), `paths` (`~/.local/bin/agy`,
  `~/.gemini/antigravity-cli`), ownership roots, and removal instructions that
  keep `~/.gemini` unless nothing else uses it. Add it to the install-order
  lists for an explicit `--antigravity`, not to the `--ai`/`--full` expansion.
- `setup.sh`: `SELECTED_AI_TOOLS`, the `--claude|--codex|--opencode|--pi` case,
  the help text (which now says `--ai` and `--full` install all of them) and
  the examples.
- `bin/dotfiles` (upgrade help), `bin/ai-update`, `bin/uninstall-tool`.
- `lib/staleness.sh`: `"antigravity agy"` in `STALE_PROGRAMS`.

**Settings (`ai-config`)**

- `lib/ai_preferences.py`: an `antigravity` component targeting
  `~/.gemini/antigravity-cli/settings.json` through the JSON merge that keeps
  the CLI's own keys, written at 0600, with an `info:` line on updates.
- `configs/antigravity-cli.json`, enforced: `showFeedbackSurvey: false`.
  Nothing about models, providers or accounts.
- `configs/antigravity-cli.defaults.json`, defaults: `altScreenMode: "never"`,
  a conservative `toolPermission`, `permissions.deny` for the usual destructive
  commands (mirroring the claude and codex defaults); `enableTerminalSandbox`
  left to the CLI's detection.
- `configs/ai/released.json` and `retired.json` as keys move.

**Shell**

- `shell/tools/antigravity.sh`, new, like `opencode.sh` and `pi.sh`: an `agy`
  function with `$AGY_FLAGS` and a message when the binary is missing. It calls
  `agy` through PATH (so a machine's launcher earlier on PATH stays in front),
  and refuses `agy update` with a pointer to `dotfiles upgrade antigravity`.
- `shell/env.sh`: `AGY_CLI_DISABLE_AUTO_UPDATE=true`, because `dotfiles
  upgrade` owns updates (docs/ai-tools-egress.md: invariants in the shell,
  changeable defaults in config).

**tmux and keys** (parity level to decide; see [agent parity](agent-parity.md))

- First: `bin/ai-update` and the agent regex in `configs/tmux.conf` (which
  gains `agy`).
- Later, once the TUI's compose and back keys are known: the keymap
  (`configs/keymap/defaults/agy.json`, `intents.json`), review, last-reply,
  compose and the badge.

**Docs**

- `docs/ai-configuration.md`: the settings file, the merge, never symlink.
- `docs/ai-tools-egress.md`: the contact table above, the update switch,
  telemetry as an account setting, the proxy variables, the install and upgrade
  fetches.
- `docs/supply-chain.md`: a moving vendor manifest, sha512 over HTTPS, no
  signature.
- `README.md`, `docs/keybindings.md`, `docs/maintenance.md`,
  `docs/customization.md`; a row in [agent parity](agent-parity.md); a note in
  [AI settings per machine](ai-settings-per-machine.md) that admin settings are
  out of scope and override the user's environment where present.

**Tests**

- Hermetic: `tests/install-antigravity.sh` (a stand-in manifest and tarball, a
  bad sha512 that fails, a working install skipped, no shadowing, no rc change,
  `--observe`, `--update`); `tests/install-ai.sh`, `tests/ai-config.py` (the
  merge keeps unknown keys and 0600), `tests/registry.sh`,
  `tests/setup-selection.sh` and its snapshot, `tests/argument-parsing.sh`,
  `tests/documentation.py` and the coverage tests.
- Containers: `agy` in the `clean_install`, `update` and `dry_run` scenarios.
  A new `tests/containers/lib/fakes/chat.py`, an OpenAI chat-completions SSE
  fake beside `messages.py` and `responses.py`, ending tool turns with
  `finish_reason: "tool_calls"`; with it a scenario runs `agy -p` against
  `AGY_LLM_GATEWAY_URL=http://localhost:PORT/v1`,
  `AGY_LLM_GATEWAY_WIRE_PROTOCOL=openai`: a public proof that the install runs
  without an account. `--slow` does a real network install.

**Kits (later)**

- `kits/harness/antigravity`: a pinned binary in a scratch layer, like
  `harness/claude` and `harness/codex`.
- `kits/auth/llm-gateway`: the `AGY_LLM_GATEWAY_*` variables beside the
  existing generic header and host arguments.

## Open

- The `tmux` parity level (none, keys only, or `ai-update` and the badge first).
- Whether merged `ai-config` keys survive the CLI's rewrites and upgrades.
  Simulated in `tests/ai-config.py` (the enforced key comes back; a default
  the CLI changed or dropped stays the machine's); not yet watched across a
  real `agy` upgrade.
- Whether old build-numbered tarball URLs stay downloadable (decides whether a
  pin is practical).
- `agy acp` and `stream-json` input were not run.

## Sources

- https://antigravity.google/docs/install, `/docs/settings`, `/docs/permissions`,
  `/docs/rules`, `/docs/mcp`, `/docs/hooks`, `/docs/sandbox`, `/docs/cli/headless`,
  `/docs/cli/troubleshooting`, `/docs/changelog`, `/docs/faq.md`, `/terms`
- Enterprise gateway: https://docs.cloud.google.com/gemini/enterprise/docs/ai-developer-tools/connect-enterprise-gateway
- Community gateways: https://portkey.ai/docs/aigw/integrations/libraries/antigravity,
  https://github.com/danistrebel/agy-litellm-gateway
