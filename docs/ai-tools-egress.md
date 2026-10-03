# AI CLIs: data egress & hardening

What Claude Code, Codex, opencode, and Pi send to third parties by default, and
how we harden each. All findings verified against each tool's own docs/source
(not memory). None of these tools is air-gapped by default.

**The guarantee is always the network layer.** Config reduces a tool's
*intended* egress; only an egress allowlist + `tcpdump` verification *proves* no
data leaves. Config is defense-in-depth, not the control of record.

Design rule we follow: **invariants → shell wrapper; sometimes-changed defaults
→ a config file** (provisioned as a copy, never a symlink, and never clobbering
an existing config).

---

## Claude Code

- **Content:** goes only to the model endpoint you configure (`ANTHROPIC_BASE_URL`,
  or `CLAUDE_CODE_USE_BEDROCK` / `CLAUDE_CODE_USE_VERTEX`). Not to Anthropic if
  you point it elsewhere.
- **Telemetry is content-safe and provider-gated:** operational metrics + error
  class names (no prompts/code), and **ON by default only on the Claude API/Teams
  path; OFF by default on Bedrock/Vertex/Foundry/AWS.**
- **Still calls home even with a custom endpoint:** WebFetch domain preflight →
  `api.anthropic.com` (`skipWebFetchPreflight: true` to stop), managed-settings
  poll → `api.anthropic.com` (org-managed only), auto-updater → `downloads.claude.ai`.

**What we ship:** `bin/ai-config claude` merges the explicitly owned preferences
from `configs/claude-settings.json`, including `DISABLE_TELEMETRY=1`,
`DISABLE_ERROR_REPORTING=1`, and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
Unlisted keys remain local. The nonessential-traffic setting also disables
Claude's automatic updater (confirmed by Claude Code 2.1.273's `doctor`). Use
`bin/ai-update claude` for an explicit native update without weakening that policy.

**Fleet enforcement (admins):** user `settings.json` is *lowest* precedence.
To enforce policy that can't be bypassed, use system managed settings at
`/etc/claude-code/managed-settings.json` (Linux) — it overrides user config.

---

## Codex

- **Content:** goes to the provider you configure. Route locally with a custom
  provider — **but Codex now requires `wire_api = "responses"`** (the OpenAI
  Responses API; `wire_api = "chat"` was removed), so the endpoint must implement
  `/v1/responses`, not just chat/completions:
  ```toml
  model_provider = "local"
  model = "your-model-id"
  [model_providers.local]
  name = "Secure local LLM"
  base_url = "https://your-internal-llm.example/v1"   # literal; no env substitution
  wire_api = "responses"
  env_key = "CODEX_API_KEY"                            # API key read from this env var
  ```
- **Telemetry — default-ON third-party egress:** stock Codex (release builds)
  defaults `metrics_exporter` to **Statsig**, exporting OpenTelemetry **metrics**
  to `https://ab.chatgpt.com/otlp/v1/metrics` (verified in
  `codex-rs/core/src/config/otel.rs`). Metrics only — `log_user_prompt` defaults
  to `false`, so no prompt/code — but still a third-party call. Traces/logs are
  off by default.
- **Updates:** Codex is installed with OpenAI's standalone installer. The
  installer owns `~/.local/bin/codex` and the versioned releases under
  `~/.codex/packages/standalone`; dotfiles owns configuration and plugins and
  does not replace the launcher's symlink. Re-run `./setup.sh --codex --force`
  to ask the official installer to update or repair the installation.

**What we ship:** portable keys in `~/.codex/config.toml` with:
```toml
[otel]
metrics_exporter = "none"
log_user_prompt = false
```
On later runs, `install-codex.sh` invokes `bin/ai-config codex`, which reconciles
only declared portable keys and preserves unlisted trust, hook, plugin, and
provider state. Backups remain in `~/.codex/backups`. Provider
profiles remain site-specific and are installed separately; Codex requires
those endpoints to implement the Responses API.

**Fleet enforcement (admins):** Codex honors a managed `requirements.toml` layer
above user `config.toml`.

---

## opencode

Full detail in **`docs/opencode-secure.md`**. V2 uses configured providers for
inference, `models.dev` for catalog metadata, and `opencode.ai` plus
`registry.npmjs.org` for update metadata and installer artifacts. `bin/ai-config
opencode` selects update notifications and disables sharing. Provider
restrictions belong to endpoint configuration. V1's `experimental.openTelemetry`
setting is unsupported in V2. The shared service has its own environment and
lifecycle; use standalone mode when each launch should inherit the shell.

---

## Pi

Two startup calls to `pi.dev`, both documented upstream:

- **Update check** — `GET https://pi.dev/api/latest-version`. Disable with
  `PI_SKIP_VERSION_CHECK=1`.
- **Install/update telemetry** — an anonymous version ping to
  `https://pi.dev/api/report-install` after a first install or a
  changelog-detected update. The same setting also controls optional provider
  attribution headers for OpenRouter, Cloudflare, and direct NVIDIA NIM
  requests. Disable with `enableInstallTelemetry: false` in `settings.json`, or
  `PI_TELEMETRY=0`.

We ship `configs/pi-settings.json` (`enableInstallTelemetry: false`),
provisioned to `~/.pi/agent/settings.json` **only when absent** — it is a rich
user-owned file (models, keybindings, trust, compaction). Note this disables the
telemetry ping but **not** the version check; those are independent.

`--offline` / `PI_OFFLINE=1` disables *all* startup network operations (update
check, package update checks, and telemetry) in one switch.

**Weaker sandbox posture than the others — worth knowing.** Pi has no built-in
permission system: it runs with the full permissions of the launching user, with
no per-action approval prompts (contrast Claude Code's permission flow and
Codex's `sandbox_mode`). Pi packages and extensions execute arbitrary code with
full system access, and skills can instruct the model to run executables.
Upstream states this plainly. Pi does prompt before trusting a project folder
that carries project-local settings/resources (recorded in
`~/.pi/agent/trust.json`, fallback governed by `defaultProjectTrust`), but that
gates *loading project config*, not what the agent may then do. Treat "review
third-party pi packages before installing" as the actual control, and
containerize if you need a real boundary.

Pi is also the only AI CLI here that is an npm package rather than a standalone
binary, so it needs Node >= 22.19 at runtime; `installers/install-pi.sh` drives
npm into `~/.pi/agent/install` rather than using `pi.dev/install.sh` (which
would edit shell rc files and can sudo-install Node — see that script's header).

---

## The network allowlist (the actual guarantee)

Egress-allowlist the host/process; deny everything else. Then verify with a
default-deny proxy or `tcpdump` on first launch of each tool.

**Permit** (per your policy): your LLM endpoint(s) · your internal OTEL collector
(if any) · `api.anthropic.com` + `downloads.claude.ai` (Claude Code, if you keep
auto-update / managed settings) · `api.github.com` + `github.com` +
`objects.githubusercontent.com` (source inspection) · `opencode.ai` +
`registry.npmjs.org` (OpenCode update check and explicit updates).

**Deny:** `ab.chatgpt.com` (Codex Statsig metrics) · `models.dev` (opencode) ·
`pi.dev` (Pi version check + install
telemetry; also `registry.npmjs.org` if you don't want `pi update` / `pi
install` to reach npm) · everything else.

`bin/opencode-contract egress` lists opencode's outbound hosts from source as a
drift signal; the Codex/Claude equivalents here are documented from source above.
