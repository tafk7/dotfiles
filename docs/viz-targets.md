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
`source.generator`, and any field the target `required`s. It makes the page's
portable form in a temporary folder (below), writes the published manifest,
hands both to the target, and records where the page went. `--dry-run` prints
the place, the files and the manifest, and changes nothing.

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

## The portable form

`viz bundle PAGE` writes it to `$VIZ_STATE/bundles/NAME/` (or `--out DIR`),
prints the path and lists what keeps the page from being portable; it exits 1
when anything does. `viz publish` runs the same code and stops on any problem.

An html page becomes one folder that loads nothing from outside itself:

- What a browser reads is copied (HTML, CSS, scripts, data, images, fonts,
  PDF, text); generators (`*.py`), hidden files and the draft's `page.toml`
  are not. A loose html file becomes `index.html`.
- Google Fonts the page links or `@import`s are downloaded into `fonts/`, with
  `fonts/fonts.css` and `fonts/MANIFEST.json` (each file's URL and sha256).
- A script or stylesheet from a CDN whose URL names an exact version
  (`d3@7.9.0`, `/ajax/libs/highlight.js/11.9.0/`, `plotly-2.27.0.min.js`) is
  downloaded into `vendor/PACKAGE@VERSION/` and recorded in
  `vendor/MANIFEST.json`. A range or tag (`@7`, `@latest`) is refused.
- Anything else loaded from outside (an API `fetch`, an unpinned script, an
  image URL) is refused, unless the target sets `network = true`. Links that
  navigate (`<a href>`) are fine.
- Relative links must resolve inside the bundle.

Downloads are cached in `~/.cache/viz/`, so bundling again needs no network.
A pdf is copied as it is, once viz has seen it has pages; an svg is checked
for outside loads like html; other formats are copied as they are.

`--format pdf` prints an html page to PDF: Chromium, the page's print CSS,
the light theme, on A4 (or `paper = "Letter"` in `config.toml`). A target that
takes pdf but not html gets the pdf without asking.

`viz look PAGE` takes screenshots in light and dark into the page's hidden
`.shots/` folder and lists what broke: script errors, failed loads, hosts the
page needs the network for, sideways scroll. `viz look --portable PAGE`
bundles first and looks at the bundle with the network blocked, which is what
a teammate will see. Both run Chromium through Playwright under `uv`, with a
pinned Playwright; the browser itself is a one-time download that `viz look`
asks you to run.

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

`viz collect` runs the collectors, in the foreground; where systemd runs a user
instance, setup installs `viz-collect.service` to run it beside `viz.service`
(`systemctl --user status viz-collect`; its own messages are in the journal).
It looks in `~/viz/live`
every 15 seconds, only at folders that are real, yours and closed to other
accounts, and runs each collector that is due in a thread of its own. A page
is due one interval after its last run started; a run still going when the
next is due makes that one skipped, never two at once, and a run past its
timeout is stopped with everything it started. One `viz collect` runs per
account. Each run's output goes to `~/.local/state/viz/collect/NAME.log`
(under `VIZ_STATE`; kept under 1 MB with one older copy) and its outcome to
`NAME.json`, which `viz status` shows for every live page, with whether
`viz collect` runs. A collector that needs something the bare environment
lacks (an ssh agent, a variable from your shell) fails there, and its log says
why.

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

### The git type

A `git` target publishes into a checkout of a repository that a static host
serves (GitHub Pages and the like). viz never clones, switches branches,
stashes or discards your work: the checkout is yours to make, and it must be
on `branch` and clean, or viz refuses.

```toml
type = "git"
description = "Team pages"
audience = "Anyone on the company network"
rules = "Work in progress is fine; nothing under embargo."
checkout = "~/src/team-pages"                # a clone you made, on branch
branch = "gh-pages"
remote = "origin"                            # pulled before, pushed after
folder = "{date}/{slug}"                     # also {project}, {year}
url = "https://pages.example.com/team-pages/{folder}/"
after = ["make", "index"]                    # optional; run in the checkout
after_timeout = 600                          # seconds
push = "ask"                                 # "auto", "ask" or "never"
message = "Publish {folder}: {title}"
```

Under a lock in the checkout's git directory (a second publish waits), viz
pulls with `--ff-only`, replaces `folder` with the page's portable form and
its manifest, runs `after` (with `VIZ_PLACE`, `VIZ_URL` and `VIZ_TARGET` set),
and commits whatever changed. If anything fails before the commit, the
checkout is reset to where it was.

Then `push` decides:

- `auto` pushes. A rejected push is rebased once onto the remote and retried;
  if that fails too, the commit stays in the checkout and viz says so.
- `ask` shows the commit and asks at a terminal. Without one (an agent's
  shell), viz commits and stops; a person pushes later with
  `viz publish --to NAME --push`, which shows what waits and asks.
- `never` commits only; pushing is yours.

The record in the draft's `page.toml` names the place, the URL, the commit
and whether it was pushed.

## config.toml

Optional, beside `targets.d/`:

```toml
author = "A. Person"                 # default author in published manifests
paper = "A4"                         # or "Letter", for html printed to pdf
[provenance]
env = ["ROLE"]                       # variables recorded in [source].env by viz path
session_env = "CLAUDE_CODE_SESSION_ID"
project_from = "PROJECT_DIR"         # project = this variable's last component, else the repository's name
```
