---
name: viz
description: >
  Deliver charts, plots, diagrams, dashboards and HTML reports to the user
  when Claude runs over ssh/tmux and the user views output through a
  connected VS Code window. Covers where to write files, which format to
  pick, how to render without installing packages, and how to open the
  result on the user's screen with `viz open`. Use whenever you produce a
  visual artifact, or when a chart or diagram would explain data, results,
  architecture or flow better than text. Pair with the dataviz skill for
  chart design. TRIGGERS: visualize, chart, plot, graph, diagram,
  dashboard, show me, render, figure, report.
allowed-tools: Bash(viz:*)
---

# Visualizations over ssh

The user's terminal cannot show images from your tool output. Write a file,
then run `viz open FILE`: it opens the file in the VS Code window connected to
this machine, or in the user's browser through a VS Code port forward. Run
`viz status` if you are unsure whether a window is connected.

## Workflow

1. `viz path NAME.ext` prints `~/viz/<today>/NAME.ext` and creates its
   directory. Use it for output unless the user wants the file in a project.
2. Write the generating script next to the output (`NAME.py`) so it can be
   re-run and edited.
3. Render, then `viz open <path>`. Pass on the line it prints (the URL or the
   fallback) in one sentence; do not describe the chart at length.
4. On revision, rewrite the same file. Pages served by `viz` reload in the
   browser by themselves; there is no need to open them again.

## Pick the format

| Content | Format | Opens in |
|---|---|---|
| Interactive chart, dashboard, report | Self-contained `.html` | Browser |
| Static chart | `.svg` (or `.png` for dense rasters) | Browser / VS Code tab |
| Architecture, flow, sequence, state diagram | `.md` with a ```` ```mermaid ```` block | VS Code; tell the user Ctrl+Shift+V previews it |
| Exploratory analysis with code and output | Executed `.ipynb` | VS Code notebook |

Default to interactive HTML for data; hover and zoom are the point of this
setup.

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
- Hand-written HTML/JS: inline all CSS and JS. If a library must come from a
  CDN, say so, because the user's network may block it.
- Mermaid: keep it to one diagram per fenced block; the VS Code preview renders
  each block.

## Boundaries

- Files under `~/viz` are served on localhost, which other accounts on a
  shared host can reach. Do not put secrets or credentials there; for
  sensitive output, keep the file in the project and open it with
  `viz open --vscode`.
- HTML/SVG/PDF outside `~/viz` (a project's own `viz/` or `reports/`
  directory, say) can be opened in place: `viz open` links the file's
  directory into `~/viz/linked/`, which serves that whole directory. Relative
  links between its pages work, and pages reload when a build rewrites them.
