# Building pages

How a page is put together on disk, fed with data, given libraries, and kept rebuildable.

## On disk

A one-off page is one file: `viz path NAME.html`, with its generator `NAME.py` beside it. A page
with parts gets a directory:

```text
NAME/
  index.html        the page (generated; viz open NAME/ opens it)
  build.py          the generator: reads data/, writes index.html
  template.html     the page's HTML and CSS with placeholders, when they are long
  data/             inputs, as JSON or CSV: a snapshot of exactly what the page shows
  vendor/           pinned libraries, with MANIFEST.json
  style.css         shared tokens and components, for a set of pages
  .shots/           screenshots from the look (hidden: viz neither lists nor serves them)
```

Keep it rebuildable: running the generator again reproduces the page. Note at the top of the
generator what it reads and writes, and where its data came from (a command, a commit, a date).

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
  `JSON.parse(document.getElementById('data').textContent)`. The page is one file and opens
  anywhere.
- **Live**, for a page the user keeps open (status, monitors, dashboards): the page
  `fetch('data.json')`es its data, and a collector rewrites `data.json`. viz tracks what a page
  loads, so rewriting the data file reloads the open page, with no need to regenerate the HTML.
  Write the file atomically (write a temp file, then rename) so a reload never reads half of it.
  Show when the data was collected on the page.
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
   and tell the user the page needs the network.

Pick versions at least two weeks old: any you knew before this conversation is old enough; if
you look versions up, skip any from the last two weeks. Load a library before the inline script
that uses it. Don't paste a library's source into the page by hand or write your own version of
one that does the job.

Fonts are the exception: link Google Fonts directly, with a real fallback stack, since the
page still reads in the fallback offline.

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

## Diffs

A page about a change can let the user open any two files side by side in the connected VS Code:
`<a href="/__viz/diff?left=/abs/path/old.py&right=/abs/path/new.py">compare</a>`. Both files
must exist under `~/projects` or `~/ref` (`VIZ_DIFF_ROOTS`).
