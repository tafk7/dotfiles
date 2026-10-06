# Spec sketch: a toolkit for running projects with coding agents — and its name

**Status:** proposed — not created. The open question is the name.
**Problem:** the conventions and small tools that make multi-agent projects
work (a desk session that plans and lands work, lanes in their own worktrees,
human gates, a register of what is current, and a visible record of work) live
inside individual projects. Each project carries its own copy, and the copies
drift. A new project, personal or work, starts from nothing.
**Goal:** one public repository, alongside Cardinal and clara, that any project
can adopt with one `init`. It holds no project data.

---

## Sketch

A Claude Code plugin marketplace plus a small CLI, in Python using only the
standard library (`uvx`, no build step). It has three layers, each opt-in and
each usable without the next.

1. **Work log.** Usable in any project, even one with a single repository.
   - Items are files, one per decision, lane, gate or chore, and the item
     keeps its plan and brief.
   - State changes are appended as events, each with who, when, why and
     evidence.
   - Each project declares its own states, from `todo/doing/done` to a long
     board.
   - Commits carry a `Work-Item:` trailer, so `git log` gives the trail from
     decision to commit.
   - It generates a single-file HTML page (board, what's waiting on me and for
     how long, worker timelines, the trail for one item) and a status-line
     segment.
   - CLI: `add`, `start`, `gate ask/answer`, `done`, `ready`, `waiting`,
     `trail`, `page`, `statusline`.
2. **Desk.** For projects with several repositories and parallel lanes.
   - Working rules as an `AGENTS.md` section a project includes: one
     integrator, lanes as `<intent>/<topic>` worktrees, human gates, never
     delete what you didn't create, report only what you read.
   - A `/desk` skill with lane create, launch and check, and an inventory.
   - Hooks for lanes: no push, no idle sleeps.
   - Write-ownership rules: which paths a lane may write.
   - Lane transitions emit work-log events.
3. **Corpus.** For projects that keep design records.
   - A register of what is current, with kinds and states.
   - Dated records that are never edited.
   - One-file issues, and eras for archived material.
   - A checker, and a mover that rewrites links.

**Boundaries:**
- A project's data (items, events, records) lives only in that project's own
  repositories and remotes, and the toolkit never knows the hosts.
- Cardinal stays separate and optional. It runs sandboxed workers, and it
  feeds the work log through a `cardinal events` stream.
- clara stays the skills library.
- dotfiles only pins the plugin and enables it.
- This repository holds no hostnames, employer terms or project vocabulary.

**Related and worth reading before fixing formats:**
- typed-knowledge's ledger design, which stores one file per record in git
  with merge drivers and treats gates as records. The toolkit could be its
  pragmatic proving ground rather than a rival.
- harness, which is an execution shell. The toolkit should not grow into one.

## The name

Neighbours: **dotfiles** (machine configuration), **clara** (skills and
prompts), **cardinal** (sandboxed agent workers), **harness** (execution
shell), **typed-knowledge** (knowledge theory and ledger).

What the name should do:
- describe the whole (desk, work log and corpus), not one role in it;
- avoid words the neighbours already use (ledger, harness, desk);
- be short as a command (`<name> work ready`, `<name> lane`,
  `<name> corpus check`);
- carry no employer or domain meaning.

| Candidate | For | Against |
|---|---|---|
| **curia** | A cardinal's administration: registers, decrees, records, approvals. It pairs with Cardinal, which runs the workers while curia keeps the books. Short, and free on tafk7. | A religious connotation; a pun some won't get. |
| desk | No new vocabulary; `/desk` is already the habit. | Names one role, not the work log or corpus; very generic. |
| atelier | A workshop: a master, apprentices, work in progress. | No link to the neighbours; long to type. |
| chancery | The office that keeps records and seals decisions. | Obscure; close to curia, but heavier. |
| logbook | Says "auditable record" plainly. | Undersells the desk and lanes. |

Leaning: **curia**.

## Next

1. Pick the name, then create the empty public repository.
2. Extract the existing generic pieces (rules, desk skill, lane tooling,
   corpus checker and mover), with tests, without changing the projects that
   use them yet.
3. Build a first version of the work log, and have one personal project adopt
   it, to prove it works outside the project it came from.
