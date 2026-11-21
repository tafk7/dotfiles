# html

The default format: anything read on a screen, from a one-screen answer to a set of pages or a
small tool. Hover, zoom, filters and deep links are the point of it, and it prints to pdf
(pdf.md). How the page is put together on disk, its generator, data and libraries are in
building.md; this file is how design.md's choices are written in HTML and CSS, and what keeps a
page portable.

## The plan as tokens

Write design.md's plan as the `:root` block at the top of the page's `<style>`: the color tokens,
the faces, and the layout idea as a one-line comment. Every element is styled through the
tokens, so a theme or a revision changes them in one place.

```css
:root {
  /* layout: one reading column; figures break wider */
  --ground: #f7f8f6; --surface: #ffffff; --ink: #1d2422; --muted: #5d6763;
  --rule: #d5dbd8; --accent: #2f6f8f;
  --display: "Literata", Georgia, serif;
  --body: "Source Sans 3", "Segoe UI", sans-serif;
}
```

## Both themes

viz serves the page as written and sets no theme: `prefers-color-scheme` from the reader's
browser decides light or dark. A `data-theme` attribute on `<html>` lets a toggle on the page, or
`viz look`, force one. Write all three blocks:

- Define the complete light palette in the bare `:root` block, before any media or
  `[data-theme]` block redefines it; a color that exists only inside one of those blocks is the
  classic unreadable-page bug.
- Redefine the tokens under `@media (prefers-color-scheme: dark)`, guarded as
  `:root:not([data-theme="light"])`, and again under `:root[data-theme="dark"]`. Set
  `color-scheme: dark` wherever the dark palette applies, so form controls and scrollbars follow.
- Style every element through the tokens, never directly inside those blocks. Color inline SVG
  and chart text from the same tokens.
- Set an explicit background on `html` and `body` from a token.
- A single-theme page omits the media and `[data-theme]` blocks and sets the background, every
  color and `color-scheme` explicitly.

## Fonts

Link Google Fonts directly (a `<link>` to `fonts.googleapis.com`, or an `@import` of it), always
with a real fallback stack. In `~/viz` the browser fetches them from Google, and the page still
reads in the fallback offline. Publishing downloads them: `viz bundle` and `viz publish` fetch
each face into the page's `fonts/`, point the page at `fonts/fonts.css`, and record the source
of every file in `fonts/MANIFEST.json`, so a published page needs neither Google nor the network
for its faces. Fonts from anywhere else are loads from outside (below): put the files in the
page's folder and use `@font-face` with a relative `url()`.

## Layout in CSS

- Lay out sibling groups with flex or grid and `gap`, not per-element margins.
- Give images `max-width: 100%`. Only wide tables, code and diagrams may exceed the screen; give
  each `overflow-x: auto` on its own container, so the page body never scrolls sideways.
- Size a one-screen app with `height: 100%` on `html` and `body`, not `100vh`.
- Headings get `text-wrap: balance`; digits that line up in columns get
  `font-variant-numeric: tabular-nums`.

## Portable

A page in `~/viz` may load from anywhere: it opens in your browser, through the forward. A
published page is its **portable form**: one folder that loads nothing from outside itself, so it
reads the same for a teammate, in a mail attachment, or offline. `viz bundle PAGE` makes it and
lists every problem; `viz publish` makes the same and refuses the page while any remains. Write
the page so it bundles cleanly:

- **Everything the page loads is in its folder**, reached by relative paths (`data.json`,
  `vendor/d3.min.js`, `../style.css` within a set). What a browser reads is copied: HTML, CSS,
  scripts, JSON, CSV, images, fonts, PDF, text. Generators (`*.py`), hidden files and the
  draft's `page.toml` are not. Another kind of file the page needs goes in `[bundle] include` in
  `page.toml` (`include = ["data/*.parquet"]`); raw inputs it does not need go in `exclude`.
- **Libraries from a CDN name an exact version** (`d3@7.9.0`, `/ajax/libs/highlight.js/11.9.0/`,
  `plotly-2.27.0.min.js`). Publishing downloads each into `vendor/PACKAGE@VERSION/` and records
  it in `vendor/MANIFEST.json`. A range or tag (`@7`, `@latest`) is refused, since the page would
  change under the reader. Inlining or vendoring (building.md) is still better: the draft then
  works offline too.
- **Nothing else from outside**: an API `fetch`, an image URL, an unpinned script, a font from a
  host other than Google's. Each is refused with its file and line, unless the target allows the
  network (`viz targets NAME` shows `network`). Links that navigate (`<a href>`) are fine.
- **Relative links resolve inside the folder.** A link to a file that is missing, or not copied,
  is refused.
- A loose html file (outside a folder page) is bundled alone, as `index.html`; anything it loads
  beside it is not copied. Make pages with `viz path`, so they are folders.

## Look and check

- `viz look PAGE` takes the light and dark screenshots and lists what broke (SKILL.md).
- `viz look --portable PAGE` bundles first and looks at the bundle with the network blocked:
  what a teammate will see. Run it before publishing to a target other than `preview` and
  `live`.
- `viz bundle PAGE` alone lists the problems without a browser; it exits 1 while any remains.

## Build cleanly

The quality floor in HTML, built without announcing it:

- Responsive down to phone width (about 400px); visible keyboard focus; `prefers-reduced-motion`
  respected.
- Close every non-void element, double-quote attributes, give every form control a stable `id`
  and a label.
- Watch selector specificity: a class selector (`.section`) and an element selector can
  silently undo each other's spacing. Prefer a few low-specificity rules and `gap`.
- For generative or decorative graphics, use Canvas, not long hand-written SVG paths.
- If the page may be printed or exported to pdf, give it print CSS (pdf.md).
