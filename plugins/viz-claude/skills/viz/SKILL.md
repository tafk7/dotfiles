---
name: viz
description: >
  Deliver charts, plots, diagrams, dashboards and HTML reports to the user
  when Claude runs over ssh/tmux and the user views output in a browser on
  their own machine (through an ssh port forward) or in a connected VS Code
  window. Covers where to write files, which format to pick, how to render
  without installing packages, and how to hand the user a URL with
  `viz open`. Use whenever you produce a visual artifact, or when a chart or
  diagram would explain data, results, architecture or flow better than
  text. Carries the page design and diagram guides (references/). Pair with
  the dataviz skill for chart design. TRIGGERS: visualize,
  chart, plot, graph, diagram, dashboard, show me, render, figure, report.
allowed-tools: Bash(viz:*)
---

# Visualizations over ssh

The user's terminal cannot show images from your tool output. Write a file,
then run `viz open FILE`. For HTML, SVG and PDF it prints a URL such as
`http://127.0.0.1:23526/2026-10-27/report.html`, which the user opens in the
browser on their own machine through an ssh port forward. Other files open as
tabs in a connected VS Code window.

## Workflow

1. `viz path NAME.ext` prints `~/viz/<today>/NAME.ext` and creates its
   directory. Use it for output unless the user wants the file in a project.
2. Write the generating script next to the output (`NAME.py`) so it can be
   re-run and edited.
3. Render, then `viz open <path>`. Pass on the URL it prints in one sentence;
   do not describe the chart at length. If it adds that no browser has
   reached viz yet, tell the user to run `viz status` for the ssh forward and
   `viz login` to sign the browser in.
4. On revision, rewrite the same file. Open pages reload by themselves when
   the page or a file it loaded (CSS, JS, images, data) changes; there is no
   need to open them again.

## Design every page

Every HTML page and diagram is designed, not just rendered. Before writing one, read:

- [references/design.md](references/design.md) for any HTML page: the treatment the request
  calls for, palette and type tokens in `:root`, light and dark themes, layout, the page's
  name, its words, and one look before publishing.
- [references/diagrams.md](references/diagrams.md) for any diagram: draw the mechanism, label
  the arrows, hand-author inline SVG with `viewBox` and `currentColor`, one claim per figure.

For charts, pair them with the dataviz skill. Where the guides and this skill differ, these
rules hold for pages served by viz:

- **Self-contained.** Inline CSS, JS and chart libraries (Plotly's `include_plotlyjs=True`) so
  the page works through the ssh forward without a CDN. Load a library from a CDN, pinned as
  design.md says, only when inlining is impractical, and tell the user it needs the network.
  Web fonts may be linked, always with a real fallback stack.
- **Diagrams are inline SVG** inside the HTML page, as diagrams.md says. Use a Mermaid `.md`
  only when the user asks for Mermaid and a VS Code window is connected to preview it.
- **One look.** Take one screenshot of the rendered page if this session can, fix what it
  shows, then publish. Check a chart's data and labels in that look.

## Pick the format

| Content | Format | Opens in |
|---|---|---|
| Interactive chart, dashboard, report | Self-contained `.html` | Browser |
| Static chart | `.svg` (or `.png` for dense rasters) | Browser (PNG: VS Code tab when connected) |
| Architecture, flow, sequence, state diagram | Inline SVG in an `.html` page (references/diagrams.md); a Mermaid `.md` only when the user asks for it | Browser; Mermaid in VS Code (Ctrl+Shift+V) |
| Exploratory analysis with code and output | Executed `.ipynb` | VS Code notebook |

Default to interactive HTML for data; hover and zoom are the point of this
setup, and the browser works without VS Code.

## Render without installing anything

Use ephemeral uv environments; never `pip install` into the system Python.

```sh
uv run --no-project --with plotly --with pandas python NAME.py
uv run --no-project --with matplotlib python NAME.py
uv run --no-project --with jupyter --with plotly jupyter nbconvert --to notebook --execute --inplace NAME.ipynb
```

- Plotly: `fig.write_html(path, include_plotlyjs=True, full_html=True)`, so the
  file needs no CDN. Set a layout `template` that suits both themes or follow
  the dataviz skill's palette.
- Matplotlib: `savefig(path, bbox_inches='tight')`; SVG for line art, PNG at
  `dpi=150` for dense scatter or heatmaps.
- Hand-written HTML/JS: inline all CSS and JS, and use relative links between
  files. If a library must come from a CDN, say so, because the user's network
  may block it.
- Mermaid, when asked for: one diagram per fenced block; the VS Code preview
  renders each block.

## Boundaries

- Never run `viz login` or paste its link into your output: the link signs a
  browser in. The user runs it in their own terminal. `viz open` and
  `viz status` print nothing secret.
- Only the user's account and their signed-in browser can read what viz
  serves. Still keep credentials out of `~/viz`: every page viz serves can
  read every other one, and a page from an untrusted source runs with that
  access, so don't open downloaded HTML through viz.
- HTML/SVG/PDF outside `~/viz` (a project's own `viz/` or `reports/`
  directory, say) can be opened in place: `viz open` links the file's
  directory into `~/viz/linked/`, so relative links between its pages work and
  pages reload when a build rewrites them. Hidden files, and files another
  account owns or can write, are never served. viz refuses to link a home
  directory, the temp root, a repository root, a hidden directory or one other
  accounts can write to; write such a file to a subdirectory of your own or to
  `viz path` instead.
- A page can ask the connected VS Code for a side-by-side diff with a link to
  `/__viz/diff?left=PATH&right=PATH` (files under `~/projects` or `~/ref`).
