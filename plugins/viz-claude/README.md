# viz

The `viz` skill for Claude Code: how to build visual pages (charts, diagrams,
dashboards, reports, walkthroughs, reviews, comparisons, small tools), each
designed for its subject, show them in the browser over an ssh forward, and
publish them to a target, with `bin/viz` from the dotfiles repo. It needs
`bin/viz` on PATH, so it is useless without the dotfiles install.

    claude plugin marketplace add tafk7/dotfiles
    claude plugin install viz@tafk7

A page has three parts that change independently: its content and design, its
format, and the target it is published to. The skill carries the first two;
targets are config files on the machine (`docs/viz-targets.md` in dotfiles),
which the skill reads with `viz targets`.

- `skills/viz/SKILL.md`: the brief-to-URL workflow: a draft folder with its
  manifest (`viz path`), one look (`viz look`), the URL (`viz open`),
  publishing under a target's rules (`viz targets`, `viz publish`), and what an
  agent must leave to the user (`viz login`, `viz stop`, pushes).
- `references/design.md`: the design direction for any format: the plan, the
  generic looks to avoid, type, both themes, layout, words.
- `references/forms.md`: page forms (answer, explainer, walkthrough, review,
  comparison, status, dashboard, explorer, report, tool, figure study, page
  sets) and how each opens.
- `references/formats/`: one guide per format. `html.md` (tokens and themes in
  CSS, fonts, what keeps a page portable) and `pdf.md` (print CSS, printing a
  page with `viz bundle --format pdf`, looking at page one); `README.md` lists
  the formats and keeps slots for those to come (pptx, typst, latex).
- `references/building.md`: generators, baked and live data, live pages and
  their collectors, libraries (inline, vendored, pinned CDN), interaction,
  pages outside `~/viz`, diffs.
- `references/diagrams.md`: drawing a mechanism as inline SVG.

Version 2 folds in the design guidance of Anthropic's `frontend-design` skill
(Apache-2.0, see `LICENSE-frontend-design.txt`), adapted to pages served by
viz, so that plugin is not needed alongside this one.
