# Tracking opencode's contract

opencode self-updates silently and ships patch releases constantly, with **no
versioned docs and no `llms.txt`**. To avoid writing integration code against a
moving target (we already got burned once assuming a non-existent
`OPENCODE_INSTALL_DIR`), treat these as the sources of truth, most → least
authoritative:

1. **The installed binary** — `opencode --version`, `opencode --help`,
   `opencode <cmd> --help`. Exact for the version actually running. This is the
   ground truth; prefer it over any doc.
2. **Config JSON schema** — `https://opencode.ai/config.json` (+ `tui.json`).
   Canonical and machine-readable, but "latest"-only (unversioned).
3. **CLI/config source, pinned by tag** —
   `https://raw.githubusercontent.com/anomalyco/opencode/<tag>/packages/opencode/src/…`
   (`cli/cmd/*.ts`, `index.ts`, `config/*.ts`). The only version-pinnable truth.
4. **Docs, as a fetchable endpoint** — the rendered `opencode.ai/docs/*` site
   blocks automated fetchers (403/000), **but it's an Astro Starlight site, so
   the markdown source is in the repo and reachable**:
   `raw.githubusercontent.com/anomalyco/opencode/<tag>/packages/web/src/content/docs/<page>.mdx`
   (e.g. `cli.mdx`, `config.mdx`, `index.mdx`). Tag-pinnable, greppable. This is
   the practical "docs endpoint" — use it, not the rendered site, when scripting.
5. **Runtime REST API** — `opencode serve` exposes an OpenAPI 3.1 spec; its
   source is `raw .../packages/sdk/openapi.json` (~1 MB). Only relevant if you
   drive the server API.
6. **Context7** (`/anomalyco/opencode`) — convenience/secondary only. A lossy,
   lagging synthesis; never the final word on a flag or schema field.

Never trust a general web-search summary for exact contract — that's the
failure mode that started this.

## Gotchas

- **Repo renamed `sst/opencode` → `anomalyco/opencode`** (SST rebranded to
  Anomaly). Old URLs still redirect, but target `anomalyco`. The install domain
  (`opencode.ai/install`) is unchanged, so our installer is unaffected.
- **No `llms.txt`** exists (upstream feature request open, unimplemented).
- GitHub's anonymous API is rate-limited to 60 req/hr (HTTP 403) — export
  `GITHUB_TOKEN` for automation.
- `releases/latest` can lag the newest tag; cross-check `opencode --version`.
- Don't hardcode config field lists — schema `$defs` change over time
  (`tools`→`permission`, `maxSteps`→`steps`, …). Read them live.

## Recommended config hygiene

Set `"autoupdate": "notify"` in `~/.config/opencode/opencode.json` so opencode
tells you when a new version exists but doesn't silently change the contract
under our tooling. Upgrade deliberately, then inspect the live contract.

## Inspection command: `bin/opencode-contract`

The repository intentionally does not carry a snapshot that silently becomes
stale. The command inspects the installed CLI or current upstream sources on
demand:

```bash
bin/opencode-contract runtime      # installed version and CLI help (offline)
bin/opencode-contract schema       # fetch and validate current JSON schemas
bin/opencode-contract docs DIR     # mirror current docs into an explicit path
bin/opencode-contract egress       # list hosts referenced by current source
```

`docs` enumerates every page via the GitHub tree API — export `GITHUB_TOKEN` or
it hits the 60 req/hr anonymous limit. For a single page, skip it and just
`curl` the raw `.mdx` URL above.

Run `runtime` before and after an opencode update and use `schema` when changing
configuration integration. Network-enforced allowlists remain the authority for
egress; the source scan is a review aid, not a runtime guarantee.
