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
under our tooling. Upgrade deliberately, then re-baseline (below).

## Drift check: `bin/opencode-contract`

Snapshots the contract (live config schema + tag-pinned CLI source + the
contract-bearing docs `cli.mdx`/`config.mdx` + the installed binary's `--help`)
into `docs/opencode-contract/`, and diffs a fresh capture against it so a change
surfaces as a reviewable git diff.

```bash
bin/opencode-contract capture      # (re)write the baseline; commit the result
bin/opencode-contract check        # diff live contract vs baseline; exit 1 on drift
bin/opencode-contract show         # print the stored baseline manifest
bin/opencode-contract docs [dir]   # mirror the FULL docs tree locally for reading
                                   # (default generated/opencode-docs, gitignored)
```

`docs` enumerates every page via the GitHub tree API — export `GITHUB_TOKEN` or
it hits the 60 req/hr anonymous limit. For a single page, skip it and just
`curl` the raw `.mdx` URL above.

Run `capture` on a machine with opencode installed and `opencode.ai` reachable
(CI can't — the site is blocked and opencode isn't installed there). Re-run
`check` after an opencode self-update; on drift, review the diff, fix any
affected installer/wrapper/aliases, then re-`capture`.
