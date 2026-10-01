# Running opencode against a secure LLM endpoint

opencode is not air-gapped by default. This describes what our tooling
configures, what is left to the provider configuration, and the network control
that actually *guarantees* no data leaves the box. Facts below were checked
against opencode's own schema and source (see `docs/opencode-contract.md`).

## What talks to the network (stock)

| Vector | Default | Destination |
|---|---|---|
| model inference | provider you configure | **your endpoint** once providers are allowlisted (below) |
| autoupdate | on | `api.github.com`, `github.com`, `objects.githubusercontent.com` |
| models.dev catalog | on | `models.dev` (model *metadata*, not prompts) |
| OpenTelemetry | **off** (opt-in) | OTLP-HTTP exporter → wherever `OTEL_EXPORTER_OTLP_ENDPOINT` points |
| Zen gateway ("free models") | opt-in (`/connect`) | `opencode.ai/zen/...` |
| share | manual (`/share`) | `opencode.ai` |
| `.well-known/opencode` | on provider auth | the provider you authenticate to |

Sentry crash reporting is in the opencode.ai **website**, not the installed CLI.

## Layer 1 — configuration

`bin/ai-config opencode` (also run by `./setup.sh --opencode`) merges
`configs/opencode.json` into `~/.config/opencode/opencode.json`, owning only the
keys it declares:

- `"autoupdate": "notify"` — the update check still reaches GitHub, but nothing
  installs silently. opencode's updater reruns the upstream installer without
  `--no-modify-path`, which would append a PATH line to the repo-owned
  `~/.bashrc`; update with `bin/ai-update opencode` instead. (`shell/env.sh`
  also puts `~/.opencode/bin` on PATH, which makes the installer skip that edit.)
- `"share": "disabled"`.

Providers, models and the provider allowlist are **not** portable: they belong
to whatever configures your endpoint. That configuration should set
`enabled_providers` to its own provider IDs, so opencode ignores every other
provider even when credentials for one exist, and should reference secrets with
`{env:VAR}` rather than storing them in the file.

OpenTelemetry stays off. It only instruments AI SDK calls; enable
`experimental.openTelemetry` yourself if you run a local collector (the OTLP
exporter defaults to `http://localhost:4318`).

## Layer 2 — the guarantee: enforce at the network

**Do not trust app config for a compliance-grade "no data leaves."** Egress-
allowlist the process/host; deny everything else.

- **Permit:** your LLM endpoint · your internal OTEL collector (if any) ·
  `api.github.com` · `github.com` · `objects.githubusercontent.com` (update check
  and explicit updates).
- **Deny:** `models.dev` · `opencode.ai` (zen/share/telemetry) · everything else.

To avoid update egress entirely, set `"autoupdate": false` locally and update
deliberately — but per project decision here, update egress to GitHub is
accepted; prompt/code/telemetry egress is not.

Then **verify empirically** before trusting it: run opencode behind a default-
deny proxy (or watch `tcpdump`/`strace`) and confirm it only reaches the
permitted hosts on startup and during a session. Measured beats documented.

## Keeping it honest over time

After `bin/ai-update opencode`, run `bin/opencode-contract egress` to list the
outbound hosts referenced in current source and `bin/opencode-contract schema`
to check the config schema, so a new endpoint surfaces for review instead of
silently widening egress.
