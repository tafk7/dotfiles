# pdf

For a page that is printed, attached, or read where a browser page will not go. A pdf is fixed:
no hover, no filters, no theme switch, no live data. Prefer html when the reader has a browser,
and make the pdf from it when they also need a file.

A pdf page comes one of two ways.

## Printed from an html page

Build the page as html (html.md), give it print CSS, and let viz print it: Chromium loads the
page's portable form with the network blocked and prints it with the page's print CSS, in the
light theme, with backgrounds, on A4 (or Letter, with `paper = "Letter"` in
`~/.config/viz/config.toml`).

```sh
viz bundle --format pdf PAGE                       # $VIZ_STATE/bundles/NAME/NAME.pdf, to look at
viz publish PAGE --to file --format pdf --out ~/outbox/NAME.pdf
viz publish PAGE --to TARGET --format pdf          # a target that takes html too, as a pdf
```

A target that takes pdf but not html gets the pdf without `--format`. The html page stays the
draft; the pdf is made fresh from it each time, so fix the page, not the pdf.

### Print CSS

Put it in one `@media print` block at the end of the page's styles, plus an `@page` rule:

- **Margins with `@page { margin: 18mm; }`.** Without it the content runs to the paper's edge.
  Leave out `@page { size: ... }`: viz sets the paper, and a size there prints the page at the
  wrong scale.
- **Width.** Media queries see the paper's full width, about 794 CSS px for A4 (816 for
  Letter), so the layout between your phone and desktop breakpoints applies; the text column
  inside 18 mm margins is narrower, about 658 px on A4. Check that the page reads at that
  width. Scripts ran first, in a 1280 px window: a chart sized in script from the window or
  its container is drawn for the screen. Draw charts in SVG with a `viewBox` and size them in CSS
  (`width: 100%; height: auto`), so they fit the paper.
- **Hide what only works on a screen**: navigation, a sticky rail, filters, buttons, the theme
  toggle, "copy" links. Show what is hidden behind them: content in a closed `<details>` or an
  inactive tab does not print, so open it or lay it out in print.
- **Page breaks.** `break-inside: avoid` on figures, table rows, cards and code blocks;
  `break-after: avoid` on headings, so none ends a page; `break-before: page` where a new part
  should start a page.
- **Links.** The reader cannot click; print the address of the ones that matter:
  `a.cite::after { content: " (" attr(href) ")"; }`.
- **Color.** Print uses the light palette. Check that the accent and the chart series still
  separate on white, and that nothing depends on hover to be understood.

## A pdf made by another tool

matplotlib (`savefig("NAME.pdf")`), a report generator, a typesetter: `viz path NAME.pdf` makes
the folder and prints `.../NAME/NAME.pdf`; write the file there, with the generator beside it,
named in `source.generator`. `viz bundle` and `viz publish` copy it as it is, once viz has seen
that it is a PDF with pages, so embed its fonts (matplotlib does by default).

## Look at page one

`viz look` shoots html and svg, not pdf. Read page one of the pdf itself (your file reader
renders a PDF page as an image). One look, as for a screen page: the margins, the first heading,
the first figure whole on its page, no screen controls, nothing cut at the right edge. If the
look shows a problem in the page, fix the html and print again. Hand over the pdf's path, or
`viz open PATH` for the user to see it in their browser.
