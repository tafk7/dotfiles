---
name: viz
description: >
  Build and deliver visual pages: charts, diagrams, dashboards, reports,
  explainers, walkthroughs, reviews, comparisons, status pages, explorers and
  small tools, each designed for its subject rather than templated. Covers
  the design direction (palette, type, layout, themes, words), the page forms
  and how to structure each, how to build them (generator scripts, data
  files, libraries, page sets), one screenshot look before publishing, and
  how to hand the user a URL with `viz open` when Claude runs over ssh/tmux
  and the user reads in a browser on their own machine or in a connected VS
  Code window. Use whenever you produce a visual artifact or an HTML page, or
  when a chart, diagram or page would explain data, results, architecture,
  progress or a decision better than text. Pair with the dataviz skill for
  chart design. TRIGGERS: visualize, chart, plot, graph, diagram, dashboard,
  show me, render, figure, report, page, walkthrough, explainer, write-up,
  HTML, design.
allowed-tools: Bash(viz:*)
---

# Visual pages over ssh

You build pages people read, scan or operate. The user's terminal cannot show
them: you write a file, `viz` serves it, and the user opens the URL in the
browser on their own machine through an ssh port forward. Every page is
designed for its subject and audience; a status memo gets the same care as a
showcase, in a quieter treatment.

## Before writing, read

- [references/design.md](references/design.md) for every page: the direction, the plan in
  `:root` tokens, the generic looks to steer away from, type, color and both themes, layout,
  words, and the quality floor.
- [references/forms.md](references/forms.md) to pick the page's form (an answer, a walkthrough,
  a review, a comparison, a status page, a dashboard, an explorer, a tool, a figure study, a set
  of pages) and what each opens with.
- [references/diagrams.md](references/diagrams.md) for any diagram: draw the mechanism, label
  the arrows, inline SVG.
- [references/building.md](references/building.md) when the page has a generator, data files,
  a library, several pages, or lives outside `~/viz`.
- The dataviz skill for any chart: form, color, marks, interaction.

## Work the brief

1. **Read it.** Name the subject, the reader and the page's one job. Pick the form and the
   treatment: utilitarian (most pages), editorial (something kept or shared), or instrument
   (scanned and operated). The user's words come first, then their project's design system, then
   your choices.
2. **Plan.** Write the plan as the `:root` block at the top of the page's `<style>`: 4 to 6 named
   colors, display and body faces, the layout idea as a one-line comment. Check the plan against
   the generic looks in design.md, and revise any part you would have produced for any similar
   page.
3. **Build** from real content and data, never lorem ipsum. Compute numbers in code, not by hand.
4. **Look once** (below), fix what the look shows, publish.
5. **Hand over** the URL in one sentence. Unless the user asks about the design, say at most one
   plain sentence on its direction, with no hex values or font names.

## Deliver with viz

1. `viz path NAME.ext` prints `~/viz/<today>/NAME.ext` and creates its directory. A page with
   parts (generator, data, assets, several pages) gets a directory: `viz path NAME/index.html`.
   Use the project's own directory instead when the user wants the page there.
2. Keep the source beside the output (`NAME.py`, its data) so the page can be rebuilt and edited.
3. Render, look once, then `viz open PATH`. It prints a URL such as
   `http://127.0.0.1:23526/2026-10-27/report.html`; pass it on, without describing the page at
   length. If it adds that no browser has reached viz yet, tell the user to press Ctrl+Alt+P in
   WezTerm, which forwards the port, and to run `viz open PATH` in their own terminal, which
   opens the page signed in (without WezTerm: `viz status` for the ssh forward, `viz login` to
   sign in).
4. On revision, rewrite the same file. An open page reloads by itself when the page or anything
   it loaded changes: CSS, scripts, images, and data it fetched. There is no need to open it
   again.

## Look once

Take one look at the rendered page before publishing, with the script beside this file (this
skill's base directory, `scripts/shoot.py`):

```sh
uv run --no-project --with playwright python SKILL_DIR/scripts/shoot.py PAGE.html
```

It writes light and dark screenshots to `.shots/` beside the page (hidden, so viz neither lists
nor serves them), prints their paths, and lists what broke: script errors, files that failed to
load, hosts the page needs the network for, sideways scroll. Read the PNGs, then fix what they
and the list show in one pass. Options: `--phone` adds a 390 px shot, `--full` the whole page,
`--selector figure` one element, `--ready CSS` waits for an app that builds itself late, `--js`
sets up a state (a tab, an open panel) first, `--root DIR` serves a page set from its top.

The look is one run, not a loop: no second screenshot, no DOM probes, no re-running a check that
passed, since the user is waiting for a link. For a page that charts real numbers, spend the
look on the chart: its data, scale and labels. A page whose point is logic (dates, money,
scoring) may also get one run of its pure function. If the user reports something broken, fix
that, look at most once more, and republish. If the script says Chromium is missing, it prints
the one-time download; ask the user before running it, or skip the look.

## Pick the format

| Content | Format | Opens in |
|---|---|---|
| Page of any form: report, explainer, review, dashboard, tool | Self-contained `.html` | Browser |
| Several related pages | A directory with `index.html` and relative links (building.md) | Browser; `viz open DIR` |
| Interactive chart | Plotly or hand-written SVG/Canvas in `.html` | Browser |
| Static chart | `.svg` (or `.png` for dense rasters) | Browser (PNG: VS Code tab when connected) |
| Architecture, flow, sequence, state | Inline SVG in an `.html` page (diagrams.md); Mermaid `.md` only when asked | Browser; Mermaid in VS Code |
| Exploratory analysis with code and output | Executed `.ipynb` | VS Code notebook |

Default to interactive HTML: hover, zoom, filters and deep links are the point of this setup,
and the browser works without VS Code.

## Render without installing anything

Use ephemeral uv environments; never `pip install` into the system Python.

```sh
uv run --no-project --with plotly --with pandas python NAME.py
uv run --no-project --with matplotlib python NAME.py
uv run --no-project --with jupyter --with plotly jupyter nbconvert --to notebook --execute --inplace NAME.ipynb
```

- Plotly: `fig.write_html(path, include_plotlyjs=True, full_html=True)` for one page, or
  `include_plotlyjs='directory'` for several pages sharing one `plotly.min.js`. Style it from
  the page's tokens or the dataviz palette, for both themes.
- Matplotlib: `savefig(path, bbox_inches='tight')`; SVG for line art, PNG at `dpi=150` for
  dense scatter or heatmaps.
- A generator script in plain Python (stdlib `html`, `json`, `string`) writes most pages; see
  building.md.

## Boundaries

- **Self-contained.** A page works through the forward without the internet: inline CSS and JS,
  vendor large libraries beside the page, and only then a pinned CDN, telling the user the page
  needs the network (building.md). Web fonts may be linked, always with a real fallback stack.
- Never run `viz login` or paste its link into your output: the link signs a browser in. The
  user runs it, or `viz open` in their terminal. Leave `forwards toggle` and `forwards close` to
  the user too: they close their tunnel. Your `viz open` only prints the URL; it, `viz status`,
  `forwards` and `forwards status` print nothing secret.
- Never run `viz stop`: the server is the account's, shared by every session, and stopping it
  signs the user's browser out. If `viz open` says the running server "has another VIZ_DIR or
  secret", report it to the user and give the file's path; do not stop the server or change its
  secret.
- Only the user's account and their signed-in browser can read what viz serves. Still keep
  credentials out of `~/viz`: every page viz serves can read every other one, and a page from an
  untrusted source runs with that access, so don't open downloaded HTML through viz.
- HTML/SVG/PDF outside `~/viz` (a project's `reports/`, say) opens in place: `viz open` links the
  file's directory into `~/viz/linked/`, so relative links work and pages reload when a build
  rewrites them. Hidden files, and files another account owns or can write, are never served.
  viz refuses to link a home directory, the temp root, a repository root, a hidden directory or
  one other accounts can write to; write such a page to a subdirectory of your own or to
  `viz path` instead.
- A page can ask the connected VS Code for a side-by-side diff with a link to
  `/__viz/diff?left=PATH&right=PATH` (files under `~/projects` or `~/ref`).
