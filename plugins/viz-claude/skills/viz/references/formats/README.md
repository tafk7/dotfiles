# Formats

A page has three parts that change independently: its content and design (design.md, forms.md,
diagrams.md, the dataviz skill), its format, and the target it is published to (`viz targets`).
This folder holds one guide per format: how to build a page in it, check it, and make it portable.

| Format | Guide | What viz does with it |
|---|---|---|
| html | [html.md](html.md) | `viz look` shoots it; `viz bundle` makes one folder that loads nothing from outside, fonts and pinned libraries downloaded into it; it can be printed to pdf |
| pdf | [pdf.md](pdf.md) | printed from an html page (`--format pdf`), or a file another tool made, which viz checks has pages |
| svg | html.md's rules for outside loads apply | checked for outside loads; `viz look` shoots it |
| png, jpg, ... | none | copied as they are |
| pptx | not written yet | copied as it is |
| typ (Typst) | not written yet | copied as it is |
| tex (LaTeX) | not written yet | copied as it is |

## A format viz has no guide for

`viz path NAME.EXT` makes the folder and its `page.toml` as for any page, with `format` from the
suffix (`report.typ` is `typ`, `paper.tex` is `tex`). `viz bundle` and `viz publish` copy the
entry file as it is, with its manifest, so the file itself must be portable: fonts embedded,
images inside it, no links to your machine. Keep the source and the build command beside it
(`deck.py`, `report.typ`) and name the command in `source.generator`. `viz open` shows html, svg
and pdf in the browser; other files open in a connected VS Code window, and images open in the
browser when no VS Code window is connected. Anything else viz cannot show: give the user the
path.

The design guidance still applies: the plan (palette, faces, layout idea), the generic looks to
avoid, the words. Only the mechanics change.

## Slots for formats to come

Each will be a file here, named after the format (`pptx.md`, `typ.md`, `tex.md`), covering: when
to choose the format, how to build it from a generator, how to check it and look at it before
handing it over, what makes it portable, and the mistakes it invites.

### pptx

Not written yet.

### typ (Typst)

Not written yet.

### tex (LaTeX)

Not written yet.
