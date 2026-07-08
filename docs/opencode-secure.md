# Running opencode against a secure local LLM endpoint

opencode is not air-gapped by default. This describes the hardened setup our
tooling provisions, and the network control that actually *guarantees* no data
leaves the box. All facts below were verified against opencode's own schema,
docs, and `package.json` (see `docs/opencode-contract.md` for how).

## What talks to the network (stock)

| Vector | Default | Destination |
|---|---|---|
| model inference | provider you configure | **your endpoint** once locked to `local` (below) |
| autoupdate | on | `api.github.com`, `github.com`, `objects.githubusercontent.com` |
| models.dev catalog | on | `models.dev` (model *metadata*, not prompts) |
| OpenTelemetry | **off** (opt-in) | OTLP-HTTP exporter → wherever `OTEL_EXPORTER_OTLP_ENDPOINT` points |
| Zen gateway ("free models") | opt-in (`/connect`) | `opencode.ai/zen/...` |
| share | manual (`/share`) | `opencode.ai` |
| `.well-known/opencode` | on provider auth | the provider you authenticate to |

Sentry crash reporting is in the opencode.ai **website**, not the installed CLI.

## Layer 1 — the hardened config (auto-provisioned)

`./setup.sh --opencode` writes `configs/opencode.json` → `~/.config/opencode/opencode.json`
**when `OPENCODE_ENDPOINT` is set** (idempotent; backs up any existing config).
It uses opencode's `{env:VAR}` substitution, so it reads these at runtime:

```bash
# ~/.shell.local (untracked — never commit)
export OPENCODE_ENDPOINT="https://your-internal-llm.example/v1"   # OpenAI-compatible
export OPENCODE_MODEL="your-model-id"                             # id your endpoint expects
```

The config:
- routes all inference to a single `local` `@ai-sdk/openai-compatible` provider →
  `OPENCODE_ENDPOINT`, model id `OPENCODE_MODEL`;
- `disabled_providers` for the cloud providers (won't load even if creds exist);
- `"share": "disabled"`;
- `experimental.openTelemetry: true` — **kept on**, because the wrapper pins the
  exporter to `localhost` (see Layer 2 note);
- `autoupdate: true` — **kept on** (see allowlist below).

OTEL stays useful locally without exporting off-box: opencode's OTLP-HTTP
exporter **already defaults to `http://localhost:4318`** when
`OTEL_EXPORTER_OTLP_ENDPOINT` is unset, so with no collector it simply no-ops
(zero egress). To send traces to an internal collector, set that env var in
`~/.shell.local`.

## Layer 2 — the guarantee: enforce at the network

**Do not trust app config for a compliance-grade "no data leaves."** Egress-
allowlist the process/host; deny everything else.

- **Permit:** your LLM endpoint · your internal OTEL collector (if any) ·
  `api.github.com` · `github.com` · `objects.githubusercontent.com` (auto-update).
- **Deny:** `models.dev` · `opencode.ai` (zen/share/telemetry) · everything else.

If you'd rather not permit auto-update egress, set `"autoupdate": false` in the
config and update deliberately — but per project decision here, update egress to
GitHub is accepted; prompt/code/telemetry egress is not.

Then **verify empirically** before trusting it: run opencode behind a default-
deny proxy (or watch `tcpdump`/`strace`) and confirm it only reaches the
permitted hosts on startup and during a session. Measured beats documented.

## Keeping it honest over time

opencode self-updates silently. `bin/opencode-contract egress` lists the
outbound hosts referenced in the tracked source, and `bin/opencode-contract
check` flags when the contract (incl. `config.mdx`) drifts — so a new endpoint
introduced by an update surfaces for review instead of silently widening the
egress surface. Re-run after updates.
