# AI CLIs: data egress & hardening

What Claude Code, Codex, and opencode send to third parties by default, and how
we harden each. All findings verified against each tool's own docs/source (not
memory). None of these tools is air-gapped by default.

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

**What we ship:** `~/.claude/settings.json` (only when absent) with the
content-safe defaults:
```json
{ "env": { "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1" } }
```
If you already have a `settings.json`, we leave it and you merge those `env`
keys. For a stricter work machine, also consider `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
(surveys+metrics+errors+feedback) and `skipWebFetchPreflight: true`. We do **not**
disable auto-update.

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
- **Auto-update:** not a factor for us — we install Codex via eget pinned in
  `eget-ai.toml` (no self-update).

**What we ship:** `~/.codex/config.toml` (only when absent) with:
```toml
[otel]
metrics_exporter = "none"
log_user_prompt = false
```
For an existing config, `install-codex.sh` warns if it lacks `metrics_exporter`
and tells you the two lines to add. The local-provider block is documented above
(not auto-shipped — `base_url` is site-specific and the Responses-API requirement
means a generic local endpoint may not work).

**Fleet enforcement (admins):** Codex honors a managed `requirements.toml` layer
above user `config.toml`.

---

## opencode

Full detail in **`docs/opencode-secure.md`**. Summary: hosted-gateway default
("free models"), a default-on `models.dev` metadata fetch, opt-in share, and
`experimental.openTelemetry` (off by default; when on, exports via OTLP-HTTP,
which defaults to `localhost:4318` = no egress). We ship a hardened
`configs/opencode.json` (provisioned when `OPENCODE_ENDPOINT` is set) that locks
providers to a local endpoint, disables share, and enables local-only OTEL.

---

## The network allowlist (the actual guarantee)

Egress-allowlist the host/process; deny everything else. Then verify with a
default-deny proxy or `tcpdump` on first launch of each tool.

**Permit** (per your policy): your LLM endpoint(s) · your internal OTEL collector
(if any) · `api.anthropic.com` + `downloads.claude.ai` (Claude Code, if you keep
auto-update / managed settings) · `api.github.com` + `github.com` +
`objects.githubusercontent.com` (opencode auto-update).

**Deny:** `ab.chatgpt.com` (Codex Statsig metrics) · `models.dev` (opencode) ·
`opencode.ai` (opencode zen/share) · everything else.

`bin/opencode-contract egress` lists opencode's outbound hosts from source as a
drift signal; the Codex/Claude equivalents here are documented from source above.
