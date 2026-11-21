# Building pages

How a page is put together on disk, fed with data, given libraries, and kept rebuildable.

## On disk

Every page is a folder: `viz path NAME.html` makes `~/viz/<today>/NAME/` with its manifest,
`page.toml`, and prints the path of its `index.html` (`viz path NAME` makes the folder alone, for
a set of pages). The generator and everything else the page needs go in the same folder:

```text
NAME/
  index.html        the page (generated; viz open NAME/ opens it)
  page.toml         its manifest: title, summary, where it came from (viz path writes it)
  build.py          the generator: reads data/, writes index.html
  template.html     the page's HTML and CSS with placeholders, when they are long
  data/             inputs, as JSON or CSV: a snapshot of exactly what the page shows
  vendor/           pinned libraries, with MANIFEST.json
  style.css         shared tokens and components, for a set of pages
  .shots/           screenshots from viz look (hidden: viz neither lists, serves nor publishes them)
```

Keep it rebuildable: running the generator again reproduces the page. Note at the top of the
generator what it reads and writes, and where its data came from (a command, a commit, a date).
Record the same in `page.toml`: `source.generator` names the command that rebuilds the page
(`"python3 build.py"`), and `source.data` may list its inputs (paths, URLs, query names) and
`source.run` the run that produced them. viz records the directory, repository and commit
`viz path` ran in; when the page is built from another tree, set `source.commit` to that
tree's.

## Generators

- Plain Python with the standard library writes most pages: `html.escape` every string that
  came from data, `json.dumps` for embedded data, f-strings or `string.Template` for markup.
- When the HTML and CSS are long, keep them in `template.html` with a few placeholders the
  generator fills (`$body`, `$data`), so the design stays editable as HTML.
- Compute every number the page shows in code, from the data, and assert the ones the argument
  rests on. A page whose numbers were typed by hand drifts from its data.
- Compute diagram coordinates in the generator on a grid (diagrams.md), from the data, instead
  of placing marks by hand.

## Data: baked or live

- **Baked**, for a snapshot that will not change: embed the data in the page as
  `<script type="application/json" id="data">...</script>` and read it with
  `JSON.parse(document.getElementById('data').textContent)`, or `fetch('data.json')` from the
  page's folder. Either way it publishes with the page.
- **Live**, for a page the user keeps open (status, monitors, dashboards): the page
  `fetch('data.json')`es its data, and a collector rewrites `data.json` on a schedule (Live
  pages, below). viz tracks what a page loads, so rewriting the data file reloads the open page,
  with no need to regenerate the HTML. Show when the data was collected on the page.
- Large data (tens of MB) slows every reload: aggregate in the generator, ship what the page
  draws, and link to the raw data instead.

## Libraries

Most pages need no library: CSS, inline SVG and a little JavaScript draw charts, diagrams,
filters and tabs. When a library does substantial work (Plotly, D3, a graph layout, a table
grid, a syntax highlighter), in order of preference:

1. **Inline** it when it is small (under about 200 KB) and the page is one file, or let the
   generator inline it (Plotly's `include_plotlyjs=True`).
2. **Vendor** it: download one pinned build into `vendor/` beside the page and load it with a
   relative `<script src="vendor/NAME.min.js">`. viz serves it through the forward without
   the internet. Record each file in `vendor/MANIFEST.json` with its name, exact version,
   source URL and sha256. A set of pages shares one `vendor/`.
3. **CDN**, only when neither works: one `<script src>` with an exact version
   (`d3@7.9.0` on jsDelivr, `d3/7.9.0/...` on cdnjs), never a range or tag (`@7`, `@latest`),
   and tell the user the draft needs the network. Publishing downloads it into `vendor/`
   (formats/html.md); a range or tag is refused there.

Pick versions at least two weeks old: any you knew before this conversation is old enough; if
you look versions up, skip any from the last two weeks. Load a library before the inline script
that uses it. Don't paste a library's source into the page by hand or write your own version of
one that does the job.

Fonts are the exception: link Google Fonts directly, with a real fallback stack, since the
draft still reads in the fallback offline. Publishing downloads them into the page's `fonts/`
(formats/html.md), so a published page needs no network for its faces.

## Live pages

A page that should stay current at one address, rewritten on a schedule, is published to the
`live` target. It gets a fixed, undated folder, `~/viz/live/NAME/` (served at `/live/NAME/`), and
a **collector**: a command `viz collect` runs every interval (the `viz-collect` user service runs
it) that writes the page, or the data it loads, at `$VIZ_OUT`.

```sh
viz publish --to live --as NAME --every 5m --cwd ~/src/proj \
    --summary "What the page shows." --run 'python3 build.py --out "$VIZ_OUT"'
viz publish DRAFT --to live --as NAME      # the draft's page.toml has a [live] table
```

```toml
[live]                        # in a draft's page.toml
run = 'python3 build.py --out "$VIZ_OUT"'
every = "5m"                  # 30s, 5m, 1h, 1d; at least 30s
cwd = "~/src/proj"            # default: where viz publish ran
```

- Publishing runs the collector once, in the foreground, and puts the page in place only when
  that run succeeds; a broken command fails then, with its output.
- The collector runs with a bare environment (`HOME`, `USER`, a short `PATH` of
  `~/.local/bin` and the system directories, and a few more), not your shell's, and no ssh
  agent: a command that needs more sets it up itself. It also gets `VIZ_OUT` (the page's
  entry), `VIZ_PAGE_DIR` and `VIZ_LIVE_NAME`.
- Write atomically (a temp file in the same folder, then a rename), so a reload never sees half
  a page.
- A live page is as private as the draft and may load from outside; a CDN script must still
  name an exact version.
- `viz status` shows each collector's last run; its output is in
  `~/.local/state/viz/collect/NAME.log`. To change the command or the interval, edit `[live]` in
  `~/viz/live/NAME/page.toml`; `paused = true` there stops collecting, and deleting the folder
  retires the page.

## Interaction

- Give every section and every item worth linking an `id`, and keep view state (selected item,
  filters, tab) in the URL hash, so a link reproduces what the user saw.
- Use native elements first: `<details>` for drill-down, `<dialog>` for a detail panel, `<input
  type="search">` for filtering, buttons for actions. Make each reachable by keyboard.
- Tooltips repeat what the mark's position and label already say, plus exact values; never put
  information only in a tooltip.
- A theme toggle, when useful, sets `data-theme` on `<html>` (design.md) and remembers the
  choice in `localStorage`.

## Diagrams from tools

Hand-authored inline SVG is the default (diagrams.md). For graphs too large to place by hand:

- `dot -Tsvg` (Graphviz, when `dot` is on PATH) from the generator, then inline the SVG and
  restyle it from the page's tokens with CSS classes; strip the fixed `width`/`height` so the
  `viewBox` scales.
- A vendored layout library (d3-force, dagre, ELK) for a graph the reader explores.
- Precompute positions in Python when the layout follows the data (layers, a timeline, a grid).

## Pages outside ~/viz

A project's own reports open in place: `viz open path/to/reports/page.html` links the directory
into `~/viz/linked/`, keeps relative links working, and reloads open pages when a build rewrites
them (see SKILL.md's boundaries for what viz refuses to link). Prefer this to copying a
project's pages into `~/viz`, which leaves a stale copy.

To publish one, it needs a manifest: a folder with its own `page.toml`, or for a loose file a
sidecar named after the whole file (`report.html.page.toml`), with the fields `viz path` would
have written (at least `title`, `summary` and `[source] generator`). A loose html file is bundled
alone, so anything it loads beside it must be in a folder page instead.

## Diffs

A page about a change can let the user open any two files side by side in the connected VS Code:
`<a href="/__viz/diff?left=/abs/path/old.py&right=/abs/path/new.py">compare</a>`. Both files
must exist under `~/projects` or `~/ref` (`VIZ_DIFF_ROOTS`).
