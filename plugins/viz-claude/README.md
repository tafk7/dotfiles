# viz

The `viz` skill for Claude Code: how to build visual pages (charts, diagrams,
dashboards, reports, walkthroughs, reviews, comparisons, small tools), each
designed for its subject, and how to show them in the browser over an ssh
forward with `bin/viz` from the dotfiles repo. It needs `bin/viz` on PATH, so
it is useless without the dotfiles install.

    claude plugin marketplace add tafk7/dotfiles
    claude plugin install viz@tafk7

What it carries:

- `skills/viz/SKILL.md`: the brief-to-URL workflow, the formats, rendering
  with uv, and what an agent must leave to the user (`viz login`, `viz stop`).
- `references/design.md`: the design direction, the plan as `:root` tokens,
  the generic looks to avoid, type, both themes, layout, words.
- `references/forms.md`: page forms (answer, explainer, walkthrough, review,
  comparison, status, dashboard, explorer, report, tool, figure study, page
  sets) and how each opens.
- `references/building.md`: generators, baked and live data, libraries
  (inline, vendored, pinned CDN), interaction, pages outside `~/viz`, diffs.
- `references/diagrams.md`: drawing a mechanism as inline SVG.
- `scripts/shoot.py`: one look before publishing, light and dark
  screenshots plus script errors, failed loads, network needs and sideways
  scroll (`uv run --no-project --with playwright python shoot.py PAGE`). It
  serves the page from disk inside the browser, so it opens no port.

Version 2 folds in the design guidance of Anthropic's `frontend-design` skill
(Apache-2.0, see `LICENSE-frontend-design.txt`), adapted to pages served by
viz, so that plugin is not needed alongside this one.
