# Design

Work as the design lead at a small studio known for giving each client a look no one mistakes
for anyone else's. Make deliberate choices about palette, type and layout that come from this
subject, and spend boldness where the brief earns it. The reader should come away understanding
something, and the design is how they get there.

This guide holds for every format. How a choice is written down in one (the CSS tokens and
theme blocks of an html page, the print CSS of a pdf) is in [formats/](formats/README.md).

## Read the request

Every page is designed; decide only the treatment.

- **Utilitarian**, for most requests: a plan, a memo, a status page, a review, a walkthrough, a
  demo. Polished, with real typographic hierarchy, considered spacing and a proper palette, but
  no gigantic hero and few flourishes.
- **Editorial**, for something the user will keep, share or present: a landing page, an overview
  for newcomers, a showcase, a game. The opening, the type and one memorable element carry more.
- **Instrument**, for pages scanned and operated rather than read top to bottom: dashboards,
  monitors, explorers, tools. The craft moves from typography to information design (below).

If unsure, a well-composed plain page is always acceptable; an over-designed one sometimes is
not.

## Ground it in the subject

- If the page, the user or the project has a design system, apply it. The user's words come
  first, then that system, then your choices. A page in a series shares the series' system on
  purpose; reuse its stylesheet.
- Name the subject, the reader and the page's single job. When the request leaves the subject
  vague, name one concrete subject yourself and build for it.
- Distinctive choices come from the subject's own world: its materials, instruments, documents
  and vernacular. A timing page can borrow a logic analyser's traces, a build report a lab
  notebook's ruled columns, a migration plan a transit map. Pick the world, then let it set the
  palette, the faces and the one device that makes the page this page.
- Include at least one detail only this subject would have (its real units and scales, its
  document conventions, its terms of art) as content, not ornament.
- Use real content. If none exists, write plausible, specific content and mark examples as
  examples.

## Plan in two passes

1. **Draft a compact system**, written down before the page (in html, as the `:root` block at
   the top of its `<style>`, formats/html.md):
   - Color: 4 to 6 named tokens (ground, surface, ink, muted, rule, accent) plus any semantic
     colors the content needs (good, warning, critical; series colors for charts).
   - Type: a display face and a body face, with their roles; a mono face only where code or
     aligned data needs one.
   - Layout: the layout idea as a one-line comment (one reading column with figures breaking
     wider; a sticky rail beside sheets; a summary strip over a scoped grid). Sketch alternatives
     as ASCII wireframes in your head or notes and pick one; settle alignment (left aligned is
     the usual answer for reading).
   - The principle: one sentence on what makes this page this page.
2. **Review the draft against the brief.** For each part, ask whether you would have produced it
   for any similar page. If so, it is a default, not a choice: replace it with something from
   the subject, and note what changed and why. Only then write the page.

## The generic looks

Generated pages cluster around a few defaults. Every one is right for some brief, and when the
user asks for one, follow them exactly. Where the brief leaves an axis free, don't spend that
freedom on:

- a warm cream ground (near `#F4F1EA`) with a high-contrast serif display and a terracotta or
  clay accent (near `#D97757`, which also reads as the assistant's own color);
- near-black with a single acid-green or vermilion accent;
- a purple-to-blue gradient hero;
- the broadsheet: hairline rules, zero radius, dense newspaper columns;
- the SaaS card kit: content chopped into identical rounded cards, one radius and one soft grey
  shadow on everything, gradient washes as decoration;
- template chrome: a tracked-out all-caps eyebrow over every heading, meta strings joined with
  middle dots, labels built as "WORD — fragment", a monospace face for every
  small label, a "→" on every link, emoji as section markers;
- Inter, Space Grotesk or the system stack as the safe face; everything centered;
- your own habit: the faces and palette of the last page you made. Across many pages, rotate
  families and worlds deliberately unless the pages belong to one set.

## Name

The page's name is its `title` in `page.toml`, which targets list it by, and its title in the
page itself (the `<title>` of an html page, its browser tab). Use the same name in both. Give it
a real name that picks this page out among dozens: a short noun phrase, typically two to four
words, or the question itself for a page that answers one. No explanation after a dash or a
colon. When trimming, keep the identifying word, not the generic one. When the user already has
a name for the thing, use it.

## Type

- Type carries the page's personality. One family or two; if two, make them clearly distinct.
  Use a display face with restraint and let its treatment (weight, width, size, setting) be part
  of the design, not a neutral vehicle.
- Choose faces for this subject, not the ones you reach for on every page, and always declare a
  real fallback stack, since the page must read offline. Each format says where faces come from
  (an html page links Google Fonts, and publishing downloads them: formats/html.md).
- Set a type scale and keep to it, with intentional weights and spacing. Keep running text near
  65 characters (under 80); give serif body text a little more line-height than sans.
- Balance the lines of headings. Use tabular figures where digits line up in columns.
- Avoid the commonest generated tells: accenting one word of a headline in italic, bold or
  color; all-caps labels; labels above content that say nothing the content doesn't.

## Color and themes

A page read on a screen has two themes, light and dark, and the reader's own setting picks one;
a print or a pdf is light. How an html page writes both is in formats/html.md.

- Define the complete palette as named tokens, a light set and a dark set with the same names,
  and style every element, every diagram mark and every chart label through them.
- Give the dark theme the same care: do not simply invert. Keep contrast legible and the accent
  working on both grounds; a saturated light-theme accent usually needs to be lighter and a
  little less saturated in dark.
- Choose neutrals deliberately: a grey with a slight bias toward the accent reads as intended.
- Semantic colors (good, warning, critical) are separate from the accent and do not count as
  it. Never encode meaning in color alone; pair it with a shape, a word or a position.
- A page that commits to one visual world may stay single-theme by choice, with every color set
  for that one ground.

## Layout

- Visual structure is information. Borders, fills, numbering, dividers, labels and position
  encode something true about the content. Numbered markers belong only to real sequences
  (steps, stages, a timeline); a rule separates things that differ.
- Space sibling groups by one gap between them, not by margins on each element.
- Keep a side gutter of at least 16px at every width. Rows wrap or stack to one column at phone
  width, about 400px.
- Only wide tables, code and diagrams may exceed the screen, each scrolling in its own
  container; the page itself never scrolls sideways.
- Make repeated elements consistent: the same edges, baselines and padding on each card or row.
  Text that outgrows its box wraps or scrolls; clipped text is a bug.
- Use borders, fills, radius and shadow by role, to set off the one element that needs it, with
  radius and depth following hierarchy rather than one value everywhere.
- Long pages get a way around: a sticky rail or contents list, an `id` on every section so a
  link lands on it.

## Complete at rest

Everything meant to be read is visible once the page has loaded; nothing waits for a scroll or a
click to appear. That first frame is what a screenshot and a shared link show. A tool or app
opens in a realistic working state with the user's real data or clearly marked examples, never
an empty shell. Size an opener to its content, not the viewport: a `100vh` hero pushes the rest
out of the first frame. Open with whatever is most characteristic of the subject (the answer,
the figure, the live state, a headline that states the finding); a big number with a small label
and a gradient accent is the default, so use it only when that number is the point.

## Motion

Use motion nobody asked for sparingly: one orchestrated moment (a single load sequence, one
reveal) lands better than scattered effects, and fade-and-slide entrances on every section or
hover lifts on every card read as generated. A section may animate in only from a visible
resting state, never from `opacity: 0` waiting on an observer. Motion that answers the reader
(opening, expanding, filtering, confirming) is welcome when it shows what changed. Respect
the reader's reduced-motion setting. A printed page has no motion, so nothing may depend on it.

## Pages that are scanned

Dashboards, monitors, explorers and tools:

- Put the summary before the detail, and what needs attention before what is fine.
- Encode state in form as well as numbers (a pill, a chip, a severity stripe), so it shows at a
  glance.
- Give sparklines and small charts the same care as type: an area fill, a faint grid, an
  emphasized endpoint, a labeled current value.
- Interactive elements look interactive; a filter shows what it scopes and that it is on.
- Align numbers right in tables with tabular figures; keep units in headers, not every cell.

## Restraint

Spend boldness in one place. Let one element be the memorable thing, keep everything around it
quiet and disciplined, and cut decoration that does not serve the brief. Before publishing, look
at the page and remove one accessory.

## Words

Words are design content: each written element does one job.

- Write from the reader's side of the screen. Name things by what people recognize, not by how
  the system is built.
- Headings state the finding when there is one ("Writes double after the cache moves"), not the
  topic ("Cache results").
- A control says exactly what it does, and an action keeps its name through the flow.
- Errors and empty states say what happened and what to do next; they don't apologize and are
  never vague.
- Prefer specific to clever, active voice, sentence case, short direct sentences. Avoid mannered
  devices: em-dash asides, "not X, but Y", colon-then-reveal, scare quotes on invented labels,
  stock phrases like "worth noting".

## Build cleanly

The quality floor, built without announcing it (each format adds its own: formats/):

- Text contrast at least 4.5:1 in every theme the page has.
- Draw charts to one scale, with every label naming a value the chart reaches. Keep marks and
  labels clear of one another and inside the drawing's bounds.
