---
name: viz
description: >
  Build, check and publish visual pages: charts, diagrams, dashboards,
  reports, explainers, walkthroughs, reviews, status pages and small tools,
  each designed for its subject rather than templated. Covers the design
  direction (palette, type, layout, themes, words), the page forms, the
  formats (html, and pdf printed from a page), how to build them (generators,
  data, libraries, page sets, live pages), one look with `viz look`, handing
  the user a URL with `viz open` when Claude runs over ssh/tmux, and
  publishing to a target under its rules (`viz targets`, `viz publish`). Use
  whenever you produce a visual artifact, an HTML page or a PDF report, or
  when a chart, diagram or page would explain data, results, architecture,
  progress or a decision better than text. Pair with the dataviz skill for
  chart design. TRIGGERS: visualize, chart, plot, graph, diagram, dashboard,
  show me, render, figure, report, page, walkthrough, explainer, write-up,
  HTML, PDF, publish, design.
allowed-tools: Bash(viz:*)
---

# Visual pages over ssh

You build pages people read, scan or operate. The user's terminal cannot show them: you write a
draft, `viz` serves it, and the user opens the URL in the browser on their own machine through
an ssh port forward. When the page should reach anyone else, you publish it to a target. Every
page is designed for its subject and audience; a status memo gets the same care as a showcase,
in a quieter treatment.

A page has three parts that change independently:

- **Content and design**: what it says and how it looks, whatever the format.
- **Format**: html (the default) or pdf, how each is built, checked and made portable.
- **Target**: where it goes and who sees it: `preview` (the user's own browser), `file`, `live`,
  or one configured on this machine. `viz targets` lists them with their rules.

## Before writing, read

- [references/design.md](references/design.md) for every page: the direction, the plan, the
  generic looks to steer away from, type, color and both themes, layout, words, and the quality
  floor.
- [references/forms.md](references/forms.md) to pick the page's form (an answer, a walkthrough,
  a review, a comparison, a status page, a dashboard, an explorer, a tool, a figure study, a set
  of pages) and what each opens with.
- [references/formats/](references/formats/README.md) for the format:
  [html.md](references/formats/html.md) for every html page (tokens, themes, fonts, what keeps
  it portable); [pdf.md](references/formats/pdf.md) when the page will be printed or handed
  over as a pdf.
- [references/diagrams.md](references/diagrams.md) for any diagram: draw the mechanism, label
  the arrows, inline SVG.
- [references/building.md](references/building.md) when the page has a generator, data files,
  a library, several pages, stays live, or lives outside `~/viz`.
- The dataviz skill for any chart: form, color, marks, interaction.

## Work the brief

1. **Read it.** Name the subject, the reader and the page's one job. Pick the form, the format
   and the treatment: utilitarian (most pages), editorial (something kept or shared), or
   instrument (scanned and operated). The user's words come first, then their project's design
   system, then your choices. If the page is for anyone but the user, find out where it is going
   now (`viz targets`, below): the target's audience and rules shape what the page may say.
2. **Plan.** Write the plan down first (in html, the `:root` block at the top of the page's
   `<style>`): 4 to 6 named colors, display and body faces, the layout idea as a one-line
   comment. Check the plan against the generic looks in design.md, and revise any part you would
   have produced for any similar page.
3. **Draft** with `viz path` (below), from real content and data, never lorem ipsum. Compute
   numbers in code, not by hand.
4. **Look once** with `viz look` (below), fix what the look shows.
5. **Hand over** the URL in one sentence, and publish if the user asked for more than a look.
   Unless the user asks about the design, say at most one plain sentence on its direction, with
   no hex values or font names.

## Draft with viz path

1. `viz path NAME.html` makes the folder `~/viz/<today>/NAME/` with a `page.toml` manifest and
   prints `.../NAME/index.html`. `viz path NAME.pdf` prints `.../NAME/NAME.pdf`; `viz path NAME`
   makes the folder alone, for a set of pages. `--title`, `--kind` (the form) and `--project`
   fill the manifest on the way. Use the project's own directory instead when the user wants the
   page there (building.md).
2. Fill in the manifest: `title` (the page's name, design.md), `summary` (one or two sentences
   on what it shows), `kind`, `audience` (who it is for, in words), and under `[source]`,
   `generator` (the command that rebuilds the page, or "by hand"). viz has filled in the date,
   the directory, repository and commit it ran in, and the host and session; leave those. viz
   never rewrites the file, and publishing appends `[[published]]` records at its end: leave
   them too.
3. Keep the source beside the output (`build.py`, its data) so the page can be rebuilt and
   edited.

## Look once

Take one look at the rendered page before handing it over:

```sh
viz look PAGE              # PAGE: the folder, its page.toml, or the html or svg file
```

It writes light and dark screenshots to `.shots/` in the page's folder (hidden, so viz neither
lists, serves nor publishes them), prints their paths, and lists what broke: script errors,
files that failed to load, hosts the page needs the network for, sideways scroll. Read the PNGs,
then fix what they and the list show in one pass. Options: `--phone` adds a 390 px shot,
`--full` the whole page, `--selector figure` one element, `--ready CSS` waits for an app that
builds itself late, `--js CODE` sets up a state (a tab, an open panel) first, `--theme light`
one theme. `--portable` looks at the page's portable form instead, with the network blocked:
what a teammate will see once it is published.

`viz look` shoots the page's entry (`index.html` for `viz path NAME.html`). In a set made with
`viz path NAME`, it shoots the file you name. A pdf it cannot shoot: read its page one instead
(formats/pdf.md).

The look is one run, not a loop: no second screenshot, no DOM probes, no re-running a check that
passed, since the user is waiting for a link. For a page that charts real numbers, spend the
look on the chart: its data, scale and labels. A page whose point is logic (dates, money,
scoring) may also get one run of its pure function. If the user reports something broken, fix
that, look at most once more, and hand it over again. `viz look` runs Chromium through
Playwright under `uv`; if it says Chromium is missing, it prints the one-time download: ask the
user before running it, or skip the look.

## Hand over in the user's browser

`viz open PATH` (the same as `viz publish PATH --to preview`) prints a URL such as
`http://127.0.0.1:23526/2026-10-27/report/index.html`; pass it on, without describing the page
at length.
If it adds that no browser has reached viz yet, tell the user to press Ctrl+Alt+P in WezTerm,
which forwards the port, and to run `viz open PATH` in their own terminal, which opens the page
signed in (without WezTerm: `viz status` for the ssh forward, `viz login` to sign in).

On revision, rewrite the same file. An open page reloads by itself when the page or anything it
loaded changes: CSS, scripts, images, and data it fetched. There is no need to open it again.

## Publish to a target

Only the user's account sees a draft. Publishing copies the page's portable form somewhere
others may see it, so publish only when the user asks for it, to the target they name or agree
to.

1. **Read the targets.** `viz targets` lists each target with who sees what is published there;
   `viz targets NAME` shows its rules in full, the formats it takes, whether a page may load
   from the network, and the fields it requires. Follow the rules: what may go there, what may
   not, who to ask. If the page breaks one, or no target fits the audience, say so instead of
   publishing.
2. **Check the page.** The manifest needs `title`, `summary` and `source.generator`, plus any
   field the target requires. `viz bundle PAGE` makes the portable form and lists every problem
   (outside loads, unpinned libraries, broken links); fix each in the page (formats/html.md).
   `viz look --portable PAGE` shows what the reader will see.
3. **Dry run, then publish.**

   ```sh
   viz publish PAGE --to NAME --dry-run   # the place, URL, files and published manifest
   viz publish PAGE --to NAME             # prints the URL or the path
   ```

   `--format pdf` publishes the html page printed to pdf (formats/pdf.md); `--set KEY=VALUE`
   sets a field of the published manifest only; `--as SLUG` picks a new place, since a republish
   to the same target reuses the last one, so its address never moves. The published copy keeps
   only the `[source]` fields the target allows: local paths, the host and the session stay in
   the draft.
4. **Hand over** the URL or path it printed, and what the target is ("published to NAME, which
   ... can see").

The built-in targets:

| Target | Who sees it | |
|---|---|---|
| `preview` | the user, in their browser | `viz open PAGE`; nothing is copied |
| `file` | whoever the file is handed to | `--out PATH`: a folder, or one `FILE.pdf` with `--format pdf` |
| `live` | the user, at a fixed address | a page a collector keeps current (building.md, Live pages) |

A configured target of the `git` type commits the page into a checkout of a repository a static
host serves. Its `push` setting decides the rest: `auto` pushes; `never` leaves the commit for
the user to push; `ask` asks at a terminal, and from your shell, which is not one, it commits and
stops. Then tell the user that the commit waits and that `viz publish --to NAME --push`, run in
their own terminal, shows it and asks. Never answer that question for them, by a pseudo-terminal
or otherwise.

## Pick the format

| Content | Format | Opens in |
|---|---|---|
| Page of any form: report, explainer, review, dashboard, tool | Self-contained `.html` | Browser |
| Several related pages | A folder with `index.html` and relative links (building.md) | Browser; `viz open DIR` |
| A page that stays current | `.html` published to `live`, rewritten by a collector (building.md) | Browser, at one address |
| Something printed, attached or filed | `.html` printed to pdf (formats/pdf.md) | Browser; any PDF reader |
| Interactive chart | Plotly or hand-written SVG/Canvas in `.html` | Browser |
| Static chart | `.svg` (or `.png` for dense rasters) | Browser (PNG: VS Code tab when connected) |
| Architecture, flow, sequence, state | Inline SVG in an `.html` page (diagrams.md); Mermaid `.md` only when asked | Browser; Mermaid in VS Code |
| Exploratory analysis with code and output | Executed `.ipynb` | VS Code notebook |

Default to interactive HTML: hover, zoom, filters and deep links are the point of this setup,
and the browser works without VS Code. A format with no guide yet (pptx, typst, latex) is still
a page: formats/README.md says what viz does with it.

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

- **Self-contained.** A draft works through the forward without the internet: inline CSS and
  JS, vendor large libraries beside the page, and only then a pinned CDN, telling the user the
  draft needs the network (building.md). Web fonts may be linked, always with a real fallback
  stack. Publishing downloads fonts and pinned libraries into the page and refuses anything else
  from outside (formats/html.md).
- **Publishing is a command, and only on the user's word.** Run `viz targets NAME` and follow
  its rules every time; never publish a draft to a shared target because it would be
  convenient, never use `--set` or an edited manifest to get round a target's requirement, and
  never push for the user where the target says `ask` or `never`. The viz server never
  publishes: no page can.
- Never run `viz login` or paste its link into your output: the link signs a browser in. The
  user runs it, or `viz open` in their terminal. Leave `forwards toggle` and `forwards close` to
  the user too: they close their tunnel. Your `viz open` only prints the URL; it, `viz status`,
  `viz targets`, `forwards` and `forwards status` print nothing secret.
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
