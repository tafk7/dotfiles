# Page forms

Most requests are one of a few forms, or a blend with one dominant job. Pick the form first:
it decides what the first frame shows, how the page is ordered and what the reader does with
it. These are starting structures, not templates; the subject still sets the look (design.md).

## Answer

One question, answered. "Why did the build slow down?", "Is the new layout smaller?"

- Opens with the answer as the headline, in a sentence that could stand alone.
- Then the one figure that shows it, then the evidence and caveats, then how it was measured.
- The figure's caption states the claim; the reader should not have to infer it.
- Usually one screen and a little more. If it needs sections, it may be an explainer.

## Explainer

How something works, for a reader who will act on it: a mechanism, a design, a concept.

- Opens with what the thing is for and the one picture of its parts in motion (diagrams.md).
- Builds from the reader's existing knowledge: define a term once, where it is first used, then
  use it consistently.
- One idea per section, each with its figure; a worked example with real values beats an
  abstract description.
- A contents rail helps past four or five sections.

## Walkthrough

A sequence the reader follows: stages of a pipeline, steps of a procedure, a change from start
to finish, a trace through a system.

- Numbered markers are right here, because the content is a sequence.
- Opens with the map: all the steps at once, each linked, so the reader knows where they are.
- Each step: what goes in, what changes, what comes out, the evidence (a snippet, a value, a
  figure), and what to notice. Keep the same internal order in every step.
- Show position persistently (a sticky step list, a progress line), and give each step an `id`.
- Long walkthroughs split into a set of pages with a shared map (below).

## Review or decision record

Findings on a piece of work, or a decision and its grounds.

- Opens with the verdict or the decision and what it asks of the reader (approve, choose, fix).
- Findings ranked by consequence, each with: the claim, the evidence (a link to the line, a
  number, a quote), the consequence, and the ask. Severity shows in form (a stripe, a chip) as
  well as in words.
- Separate what was checked and held from what failed or remains open.
- Rounds of review are pages in a set, each linking to the last, with a short "changed since"
  at the top.

## Comparison or proposal

Options weighed, or a change proposed against the current state.

- Opens with the recommendation, then the difference that decides it.
- Draw the difference (diagrams.md): before and after, or the options side by side with the
  edge each adds or removes. A box per option with nothing connecting them is a list, not a
  comparison.
- A criteria table with the options as columns, and the deciding rows set off.
- Costs, risks and what is reversible, stated plainly.

## Status or timeline

Where things stand: progress since the last look, what is waiting on whom, what happens next.

- Opens with what changed and what needs the reader, ahead of everything that is fine.
- Time as a picture: a lane per workstream on a shared time axis, a now-line, events as marks
  labeled with what they were. Who or what each item waits on, encoded consistently.
- Next steps with owners and conditions, not just a list.
- If it will be refreshed, make it a live page (building.md) so the user keeps one tab.

## Dashboard or monitor

Many measures, scanned repeatedly.

- A summary strip first: the few numbers that say whether things are fine, each with its trend
  or comparison, not a bare figure.
- Filters in one row that visibly scope everything below them; state in the URL hash so a link
  reproduces the view.
- Charts sized by importance, sharing scales where they are compared; tables for detail, sorted
  by what matters, with the costliest or worst first.
- Live data through a fetched JSON file the page rereads on reload (building.md).

## Explorer or reference map

A system, inventory or corpus the reader navigates: components and their links, a catalogue,
an API surface.

- An overview that shows the whole (a map, a grouped index, a matrix), then search or filter,
  then a detail view for the selected item.
- Every item has an `id` and a stable link; the detail view shows its relations as links.
- Large graphs need a layout engine or precomputed positions (building.md, diagrams.md);
  past roughly 40 nodes, group or filter before drawing everything.

## Data report or chart

One or a few charts that carry a finding.

- The chart's title states the finding; the subtitle names the data and units.
- Annotate the point the finding is about, directly on the chart.
- Follow the dataviz skill for form, color and marks; add a table or download of the data when
  the reader may want the numbers.

## Tool or small app

Something the reader operates: a calculator, a picker, a schedule, a playground.

- Opens in a realistic working state with real data or marked examples, never an empty shell.
- Controls look like controls, say exactly what they do, and show their result immediately.
- Keep the logic in a pure function you can run once against a known case; keep state in the
  URL hash when sharing a view matters.

## Figure study

Several attempts at one hard figure, when the right picture is not obvious.

- A directory with `attempt-1/`, `attempt-2/`, ..., each a page with its generator, and a
  `NOTES.md` recording what each attempt tried, its strengths and its failures.
- An index page that shows the attempts side by side at the same scale, so the user can choose.
- The chosen one moves to `chosen/` and its generator becomes the source of truth.

## A set of pages

Several pages that belong together: a walkthrough in stages, review rounds, a hub over reports.

- A directory with an `index.html` hub that says what the set is and links every page with a
  line on what it holds; `viz open DIR` opens the hub.
- One shared stylesheet (`style.css`) for the set's tokens and components; each page links it,
  and edits to it reload every open page.
- The same navigation on every page: back to the hub, previous and next where the pages are a
  sequence. Relative links only.
