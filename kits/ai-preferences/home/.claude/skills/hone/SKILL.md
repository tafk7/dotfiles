---
name: hone
description: >
  Re-derive a system's architecture from first principles, eliminating
  composition debt. Trace the current system, critique it against a debt
  taxonomy, derive an ideal architecture in isolation, reconcile ideal
  with reality, and produce a gated implementation plan. Human-invoked;
  analyzes and plans only — execution happens in a fresh session.
  TRIGGERS: hone, rearchitect, rethink, composition debt, re-derive.
---

# Hone

Re-evaluate a system against what it should be, then produce a plan to
close the gap. Self-contained: every step is an inline instruction, not
a dispatch to another skill. Hone analyzes and plans — it never edits
code. The implementation plan is the terminal artifact.

## Flow

```
TRACE
  │ gate: user confirms the map is accurate
  ├──────────────► CRITIQUE ─────────────────┐
  │                gate: user selects findings │
  └──────────────► SPEC ─► REDESIGN            │
                   (isolated from CRITIQUE)    │
                            │                  ▼
                            └───────────► RECONCILE
                                          gate: user approves pitch
                                               │
                                               ▼
                                             PLAN (terminal)
```

After TRACE, the two tracks run concurrently. CRITIQUE is done inline by
you. SPEC → REDESIGN dispatches a subagent that works while you critique.
RECONCILE waits for both tracks to finish.

**The isolation rule is the whole point:** the redesign must be derived
from purpose alone. If the architect sees the current system or its
flaws, it anchors on them and you lose the fresh-eyes design. Keep
SPEC → REDESIGN walled off from CRITIQUE. Critique findings inform
RECONCILE, never REDESIGN.

---

## Artifacts

A hone produces **five** files, all named `<topic>.<stage>.md`:

| Stage | File | Written at |
|---|---|---|
| TRACE | `<topic>.trace.md` | end of TRACE |
| SPEC | `<topic>.problem-space.md` | end of SPEC |
| REDESIGN | `<topic>.architecture.md` | subagent returns |
| RECONCILE | `<topic>.design-pitch.md` | on gate approval |
| PLAN | `<topic>.impl-plan.md` | terminal |

Resolve the directory **once, at the start**, first hit wins — call it
`$HONE` for the rest of this skill:

1. `$HONE_DIR`, if set.
2. `.agents/hone/` — if the project has an `.agents/` directory.
3. `./hone-artifacts/` — otherwise. Say so in your opening message, so
   the user can redirect before you write anything.

Create the directory if it does not exist. If the project keeps agent
scratch under a different name, prefer that over inventing a new one.

**Artifacts are working state, not deliverables.** They usually land in
a gitignored scratch area, which means they are evictable — so anything
that must outlive the hone belongs somewhere durable. See GRADUATION at
the end.

---

## TRACE — map what exists

Map the flow the user wants to rework. Read the relevant source and
produce:

1. **Component inventory** — table: Name │ Location │ Responsibility │ I/O
2. **Dependency graph** — box-drawn ASCII diagram of what calls what
3. **Data-flow narrative** — what enters, how it transforms, what exits
4. **Boundary audit** — where validation happens today, and where it doesn't

Save to `$HONE/<topic>.trace.md`, and **state the commit you analysed**.
A trace is only meaningful against a known revision. If the working tree
is dirty, analyse a clean copy (`git archive HEAD`) rather than the live
tree, and say which — an in-flight edit from another session will
otherwise show up as a finding.

RECONCILE consumes this, and it is the artifact most worth re-reading
later: it is the only record of what the system looked like before.

> **Gate:** Present the map. User confirms it is accurate and complete
> before proceeding. A wrong map poisons everything downstream.

---

## Track A — CRITIQUE (inline)

Walk the traced flow. Evaluate each component against the debt taxonomy.

| Category              | Signal                                                                |
|-----------------------|-----------------------------------------------------------------------|
| Redundancy            | Two components independently solve the same problem                   |
| Boundary blur         | Ownership unclear — who validates? who owns the shape?                |
| Interface cruft       | Interfaces preserved that the composed system no longer needs         |
| Flow friction         | Unnecessary hops, redundant parsing, data copied through inert layers |
| Abstraction mismatch  | A component's model reflects an outdated understanding of the domain  |
| Purposeless structure | More indirection/parameterization/abstraction than the problem needs  |

At each component ask: Does it duplicate work done elsewhere? Is the
data-contract owner clear at this boundary? Does every interface it
exposes still serve a consumer? Does data pass through without meaningful
transformation? Does its abstraction match the current domain? Does it
justify its existence with a real requirement?

For each finding, produce:
- **Category** (from the taxonomy — if it doesn't fit cleanly, name the
  closest and say why)
- **Location** in the flow
- **What is wrong** — one concrete sentence
- **Why it matters** — impact on correctness, performance, or maintainability

Output a numbered list of findings. **No proposed solutions** — that is
RECONCILE's job.

> **Gate:** User selects which findings to address. Unselected findings
> are dropped from scope.

---

## Track B — SPEC → REDESIGN (isolated)

### SPEC (inline)

Write an implementation-agnostic problem statement for the target system:
what it must accomplish, its inputs and outputs, its invariants and
constraints, and its success criteria.

**Constraint:** purely purpose-driven. No critique findings, no current
flaws, no current component names, no file paths. This document is the
architect's *only* input — contaminating it with current-system
knowledge defeats the redesign.

Save it to `$HONE/<topic>.problem-space.md`.

### REDESIGN (subagent)

Spawn a subagent (via the Agent tool) to derive the ideal architecture.
Give it **only** the problem statement — no trace, no file paths, no
codebase access. Inline these instructions into the subagent prompt:

> You are a software architect. Working from the problem statement below
> and nothing else, derive the ideal architecture from first principles.
> Do not look at any existing code. Define components, their
> responsibilities, the interfaces/contracts between them, and where
> validation lives. Justify each component by the requirement it serves.
> Produce: a box-drawn component diagram, a component responsibility
> table, and the boundary/validation model. Output only the architecture.
>
> PROBLEM STATEMENT:
> <paste the contents of $HONE/<topic>.problem-space.md>

Save the subagent's result to `$HONE/<topic>.architecture.md`.

---

## RECONCILE — merge the three streams

Begin only after both tracks complete. Inputs:
- Current architecture (`$HONE/<topic>.trace.md`)
- Ideal architecture (`$HONE/<topic>.architecture.md`)
- Selected critique findings (from CRITIQUE)

Three knowledge streams converge: what exists, what fresh eyes designed,
and what's wrong. The findings decide which current-vs-ideal deltas matter
and how aggressively to migrate.

1. Map ideal components to current ones. Identify what aligns, what is
   missing, what is surplus.
2. For each delta, check it against the critique findings. Deltas that
   resolve a selected finding take priority; deltas that improve areas
   with no known flaw are lower priority.
3. Assess migration cost for each prioritized delta.
4. Produce the proposed architecture: the ideal, constrained by migration
   reality and prioritized by findings.
5. Call out where the proposal departs from the ideal, and why.

Produce the **design pitch**:

```
1. CURRENT architecture   (box-drawn diagram)
2. IDEAL architecture     (box-drawn diagram)
3. PROPOSED architecture  (box-drawn diagram)
4. CHANGE MANIFEST
     REMOVING — why it is gone
     ADDING   — what problem it solves
     MOVING   — why the new location is better
     MERGING  — why they were redundant
5. RATIONALE
     Why proposed over current
     Where proposed deviates from ideal, and why
```

> **Gate:** User approves the design pitch. On approval, write it to
> `$HONE/<topic>.design-pitch.md`. On rejection, revise and
> re-present.

---

## PLAN — terminal artifact

From the approved design pitch alone, write an implementation plan to
`$HONE/<topic>.impl-plan.md`. It must be self-contained: a fresh
session reading only the design pitch, this plan, and the source files
should have everything it needs to execute. Order tasks by dependency
(upstream modules first); make each task independently committable with
explicit verification criteria.

State the commit the plan is baselined against. A plan that says
"self-contained" and cites stale line numbers is worse than one that
admits its baseline.

Hone stops here. Execution happens in a fresh session.

---

## GRADUATION — after the plan lands

Not part of the hone run; do this when the work is done, or tell the
executing session to.

The five artifacts are working state in a scratch directory. Left there,
they become a shadow archive that outlives its accuracy — the plan is
self-described as self-contained, so a future session trusts its stale
claims. When the plan lands, move them somewhere durable, and record
what **changed under contact**: the tasks refused on evidence, the
premises that turned out false, the baselines that were wrong. That
delta is the most valuable thing a hone produces and the first thing
lost.

If the plan is gated rather than executed, keep the plan where open work
lives and archive the rest. If the project has no such place, say so
rather than leaving the artifacts in scratch.

---

Re-derive from first principles. Trace fully. Spec cleanly. Keep the
redesign isolated. Pitch before you plan.
