# Publishing viz pages

A page has two stages: a **draft** in `~/viz`, which only your account can see,
and a **publication** to a **target**, which decides who sees it. viz ships the
mechanism and three built-in targets. It ships none of your hosting places:
those are config files of your own.

## Drafts and their manifest

`viz path report.html` makes `~/viz/<today>/report/` and prints the path of
its `index.html`. Beside it, `page.toml` is the page's manifest:

```toml
title = "Cache hit rate after the fix"
summary = "Hit rate per day for the week before and after the change."
kind = "report"
format = "html"
entry = "index.html"
project = "proj"
audience = "the team"
date = 2026-11-20
updated = 2026-11-20

[[links]]
label = "The pull request"
url = "https://example.com/me/proj/pull/51"

[source]
dir = "/home/me/src/proj"
repo = "/home/me/src/proj"
commit = "586ff19"
dirty = false
remote = "git@example.com:me/proj.git"
host = "box1"
generator = "build.py"
```

viz fills in what it knows when it makes the stub: the folder, format and
entry, today's date, and `[source]`, the directory, repository, commit, host and
session it was made from. You (or the agent) fill in `summary` and
`source.generator`. viz writes the stub once and never rewrites it; publishing
appends a `[[published]]` record at the end. A loose file outside a folder
page has a sidecar named after the whole file: `report.html.page.toml`.

Fields for one target only go in a `[to.NAME]` table, and `[bundle]` adjusts
what is copied (`include = ["data/*.parquet"]`, `exclude = ["data/raw/*"]`).

## Publishing

```bash
viz targets                                  # every target and who sees it
viz targets NAME                             # one target, with its rules in full
viz publish PAGE --to file --out ~/outbox/report --dry-run
viz publish PAGE --to file --out ~/outbox/report
```

`viz publish` refuses a page without `title`, `summary` and
`source.generator`, and any field the target `required`s. It copies the page
into a temporary folder (what a browser reads: HTML, CSS, scripts, data,
images, fonts; not generators, hidden files or the draft's manifest), writes
the published manifest, hands both to the target, and records where the page
went. `--dry-run` prints the place, the files and the manifest, and changes
nothing.

The published manifest is built from, lowest first: `author` in
`config.toml`, the target's `[manifest]`, the draft's fields, the draft's
`[to.NAME]`, then `--set KEY=VALUE`. viz then sets `date` (the first
publication to this target), `updated` (today), and keeps only the `[source]`
fields the target lists in `provenance` (by default `commit` and
`generator`). Local paths, the host and the session stay in the draft.

Publishing again to the same target reuses the last place, so the address
never moves; `--as SLUG` picks a new one.

Publishing is a command only. The viz server never publishes: any page it
serves can call it, so a publish endpoint would let one page copy another
draft to a shared site.

## Built-in targets

| Target | Who sees it | |
|---|---|---|
| `preview` | you, in your browser over the ssh forward | `viz publish PAGE --to preview` is `viz open PAGE` |
| `file` | whoever you hand the file to | `--out PATH`: a folder, or one `FILE.pdf` for a pdf |
| `live` | you, at a fixed address in your browser | `~/viz/live/NAME/`, rewritten by a collector ([below](#live-pages)) |

## Live pages

A live page has a fixed, undated place, `~/viz/live/NAME/`, served at
`/live/NAME/`, and a **collector**: a command run every interval that
rewrites the page (or the data it loads). An open page reloads when its file
changes.

```bash
viz publish --to live --as usage --every 5m --cwd ~/src/proj \
    --summary "Token usage over time." --run 'make-usage-page "$VIZ_OUT"'
viz publish DRAFT --to live              # the draft's page.toml has a [live] table
```

The page's own `page.toml` is the registration:

```toml
[live]
run = 'make-usage-page "$VIZ_OUT"'   # run by sh -c, in cwd
cwd = "~/src/proj"                   # default: where viz publish ran
every = "5m"                         # 30s, 5m, 1h, 1d; at least 30s
timeout = "10m"                      # default: the interval, at most 30m
paused = false                       # true stops collecting; the page stays
```

Edit it in place to change the command or the interval; delete the folder to
retire the page. `--run`, `--every` and `--cwd` override a draft's `[live]`
table. Without a draft, `--as`, `--run`, `--every` and `--summary` are needed
(`--title` defaults to the name, and the command is the page's generator).

Publishing runs the collector once, in the foreground and with the same
timeout, in a staged copy of the page, and puts the page in place only when
that run succeeds. A broken command fails then, with its output, and an
earlier registration stays as it was. A republish replaces the page whole,
and only a folder viz published.

A collector gets `VIZ_OUT` (the page's entry, `index.html` unless the draft
names another), `VIZ_PAGE_DIR` and `VIZ_LIVE_NAME`, and otherwise a bare
environment: `HOME`, `USER`, `LOGNAME`, `SHELL`, `LANG`, `TZ`,
`XDG_RUNTIME_DIR` and `PATH=~/.local/bin:/usr/local/bin:/usr/bin:/bin`. The
first run and every later one see the same, so a command that needs more sets
it up itself (`. ~/env.sh && make-usage-page "$VIZ_OUT"`); no ssh agent is
passed. It should write the page atomically (a temporary file, then a
rename), so a reload never sees half a page.

## Configured targets

A target of your own is a file, `~/.config/viz/targets.d/NAME.toml` (or under
`VIZ_CONFIG`), named by its stem. Keys every type takes:

```toml
type = "git"
description = "Team pages on the company GitHub Pages"
audience = "Anyone on the company network"      # who can see what is published
rules = """
What may go here and what may not, who to ask, how long it stays.
"""
formats = ["html", "pdf"]                       # what it takes; default: any
network = false                                 # may a page load from outside?
provenance = ["commit", "generator", "remote"]  # the [source] fields it keeps
required = ["project"]                          # beyond title, summary, source.generator

[manifest]                                      # defaults for the published page.toml
author = "A. Person"
```

`preview.toml`, `file.toml` and `live.toml` are refused: the built-in targets
cannot be redefined. A file that does not load is listed by `viz targets` and
`viz status` with the reason, and cannot be published to.

## config.toml

Optional, beside `targets.d/`:

```toml
author = "A. Person"                 # default author in published manifests
[provenance]
env = ["ROLE"]                       # variables recorded in [source].env by viz path
session_env = "CLAUDE_CODE_SESSION_ID"
project_from = "PROJECT_DIR"         # project = this variable's last component, else the repository's name
```
