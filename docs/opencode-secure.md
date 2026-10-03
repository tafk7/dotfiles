# OpenCode V2 with a private endpoint

Dotfiles owns portable preferences. Endpoint configuration owns providers,
models, credentials and provider restrictions. OpenCode also performs network
operations outside model inference, so provider restrictions alone do not
establish a network boundary.

## Configuration

`bin/ai-config opencode` merges `configs/opencode.json` into the global config:

- `update: "notify"`: announce updates, without installing automatically.
- `share: "disabled"`: retain the explicit sharing policy. Session sharing is
  currently unavailable in V2.

Before V2 is installed, the reconciler uses the supported V1 `autoupdate`
spelling. Update with `bin/ai-update opencode`, which passes `--no-modify-path`.
Shell startup files remain managed by dotfiles.

Use V2 `providers` with environment references such as `{env:MY_API_KEY}`.
The legacy `enabled_providers` allowlist remains supported; native policies
can express provider restrictions with ordered `provider.use` statements.
These restrictions do not sandbox plugin code or block catalog/update traffic.

V1 `experimental.openTelemetry` is unsupported in V2; do not rely on the old
setting or the former AI SDK telemetry behavior.

## Service environment

V2 normally starts a shared background service, which can outlive the shell
that supplied its credentials. Validate key rotation, proxy configuration and
service restarts when using it. `opencode --standalone` uses a private server;
`opencode service set disabled true` makes private servers the local default.
When a proxy is configured, exclude `localhost,127.0.0.1,::1` with `NO_PROXY`.

## Network destinations

- Model requests use the configured provider endpoint.
- Stable update metadata comes from `opencode.ai/update/api/latest/cli/npm`.
- The installer comes from `opencode.ai/v2/install`; binaries are npm artifacts
  under `registry.npmjs.org/@opencode/`.
- The model catalog uses `models.dev`; additional integrations/plugins have
  their own network behavior.
- `bin/opencode-contract` explicitly uses GitHub source/API archive services.

If a deployment requires restricted egress, enforce it with the host/proxy
policy and measure startup and request traffic. Disabling model providers does
not disable all other networking. To disable update checks, use `update:
"disable"` in the effective configuration; the dotfiles reconciler otherwise
restores its declared notification preference.

See [opencode-contract.md](opencode-contract.md) for release-matched source
inspection. Its literal-host scan is evidence for review, not a complete audit.
