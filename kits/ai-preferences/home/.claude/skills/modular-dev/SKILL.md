---
name: modular-dev
description: >
  Modular development paradigm — module structure, hermeticity, interface
  contracts, parallel agent execution. Loaded when work involves
  multi-module changes, scoping across module boundaries, defining
  interfaces, or planning parallel agent assignments. Informs SCOPE,
  DESIGN, and DECOMPOSE with structural discipline.
  TRIGGERS: modular, module contract, module boundaries, hermeticity,
  parallel agents, scope the work, interface contract, bounded context.
---

# Modular Development

The codebase is a persistent structure of modules connected by dependency
edges. Every development task — feature, fix, refactor — operates on a
scoped subset of that structure. Modules are the unit of ownership,
testing, and replacement.

## The Module

A module is a bounded unit of ownership with encapsulated internals and
a public interface. Five attributes define it:

**Interface** — the public surface other modules depend on. In Python:
`__all__` and public names. In Rust: `pub` items. In TypeScript:
`export` statements. The interface is the sole coupling point between
modules — the separation of what a module promises from how it delivers.

**Precondition (ready-when)** — what must hold before work begins.
Typically upstream interface stability: modules this module imports from
must have their interfaces finalized.

**Postcondition (done-when)** — what the module guarantees upon
completion. Tests pass, types check, interface contract satisfied.

**Artifact** — verified output proving the module is done. The passing
test suite, the type-checked interface, the built binary.

**Dependency edges** — the `depends-on` relationships wiring the module
into the structure. Module A depends-on module B means A imports from B.
Dependencies are inferred from imports.

## Hermeticity

A module depends only on its declared inputs and produces only its
declared outputs. No hidden side effects, no ambient state access.
Hermeticity is the master property — every other desirable property
follows from it:

**Parallelism** — modules with no dependency relationship can execute
simultaneously. No shared mutable state, no interference.

**Reproducibility** — same inputs produce same outputs, regardless of
when or where.

**Safe agent assignment** — an agent given a hermetic module
specification has everything it needs. Its context is self-contained.

**Substitution** — any implementation satisfying the interface is a
valid replacement. The rest of the system depends on the interface,
never on internals.

### Hermeticity Violations

- Reading global config not declared as an import
- Accessing environment variables not in the interface
- Filesystem paths not declared in scope boundary
- Singletons or module-level mutable state shared across modules
- Implicit coupling to network services or databases

## Scoping Work

Every task starts by identifying the affected modules:

- **New** — module that doesn't exist yet, needs creation
- **Modified** — module whose interface or internals are changing
- **Stable** — module outside scope, provides a fixed interface

Stable modules are load-bearing constraints: their interfaces are
facts, not negotiations. Treating them as fixed prevents scope creep
and ensures scoped work can be verified in isolation.

## Interfaces First

Define or verify every affected module's interface before touching
implementation. This is the critical discipline — correct interfaces
before internals is what makes parallel execution safe and rewrites
cheap.

For **new modules**: write the interface spec — imports, exports,
types, responsibilities. Downstream modules code against this spec
before the module exists.

For **modified modules**: write the interface diff. Every interface
change must be evaluated for downstream impact.

For **shared types**: if the change requires types crossing module
boundaries, the foundation module updates first.

## Parallel Execution

Two modules are **independent** if neither depends (directly or
transitively) on the other. The set of all modules whose dependencies
are satisfied is the **frontier** — work ready to execute now.

Group independent modules into **waves**. Modules within a wave can
scatter to parallel agents. Waves execute sequentially.

The **scatter/gather** pattern: fan out independent module assignments
to parallel agents, collect their artifacts when complete. Each agent
works hermetically within its module's scope boundary.

The **critical path** — the longest chain of dependent modules —
determines minimum completion time even with infinite parallelism.
Optimize by reducing sequential dependencies or splitting large modules.

## Module Contract Template

When assigning a module to an agent:

```
MODULE: <n>
LOCATION: <path>

INTERFACE:
  imports: <upstream modules and what is imported from each>
  exports: <public names/functions this module provides>

PRECONDITION (ready-when):
  <what must be true before work begins>

POSTCONDITION (done-when):
  <definition of done — tests, types, behaviors>

SCOPE BOUNDARY:
  IN SCOPE: <files/directories the agent owns>
  OUT OF SCOPE: <files/directories the agent must not touch>
```

## Boundaries and Bounded Contexts

Modules cluster into regions with shared vocabulary — **bounded
contexts**. Within a context, terminology is unambiguous and internal
types are shared. Between contexts, communication uses explicit
**adapters** that translate between vocabularies and data shapes.

**Seams** are natural substitution points — boundaries where one
implementation can be swapped for another without affecting the rest.
Identify seams when decomposing: where can you swap, insert a test
double, or split?

## Verification: Gates and Contracts

**Verification gates** (automated) — tests pass, types check,
postconditions hold. Binary pass/fail. Every module completion
triggers one.

**User gates** (manual) — review design before planning, review plan
before implementation. Prevent cascading errors.

Gate placement:
- After interface design: user gate
- After each module completion: verification gate
- After complex changes: user gate before integration
- After integration: verification gate (full suite)

On gate failure: fix within the failing module, re-gate. Do not
propagate failures downstream.

## Anti-Patterns

**Interface-last development.** Building internals first, "discovering"
the interface afterward. Prevents parallel execution. Guarantees
integration pain.

**Ambient state coupling.** Modules reading global config, env vars,
singletons, or filesystem paths not in their interface.

**Scope creep past the boundary.** An agent fixing something outside
its declared scope.

**Skipping gates.** Pushing downstream before verification completes.

**Monolithic modules.** Modules too large to parallelize. Split along
seams.

**Circular dependencies.** Cycles destroy the DAG property. Fix by
merging the coupled modules or extracting the shared concern.

## Vocabulary

**Unit:** module (bounded ownership, encapsulated internals, public
interface).

**Contract:** interface (public surface), precondition (ready-when),
postcondition (done-when), artifact (verified output).

**Dependency:** depends-on (A imports from B), upstream (toward
sources), downstream (toward consumers).

**Composition:** module structure (DAG of modules), plan (structure +
execution strategy + assignment).

**Parallelism:** independent (no transitive dep → safe to parallelize),
frontier (ready now), scatter/gather (fan-out, collect).

**Isolation:** hermetic (no hidden deps), bounded context (module
cluster sharing vocabulary), seam (substitution boundary).

**Verification:** assert (hard check), gate (must-pass before
downstream), satisfy (structural conformance to interface).

**Substitution:** adapter (translation at bounded context boundary).

## Theoretical Foundations

Six independent traditions arrived at the same core abstraction: typed,
hermetic units of work composed through explicit contracts into a
directed acyclic graph.

- **Component engineering** (Szyperski) — contractually specified
  interfaces and explicit context dependencies
- **Build systems** (Bazel, Buck2, Nix) — target graphs where nodes
  are artifacts and edges are dependencies
- **Dataflow systems** (Dagster, Airflow) — DAGs of typed
  transformations
- **Type theory / ML modules** — signatures vs structures; any
  implementation satisfying the signature is a valid substitute
- **Domain-Driven Design** (Evans) — bounded contexts, adapters,
  ubiquitous language
- **Category theory** — modules as morphisms, commutative diagrams
  as parallelism, tensor products as parallel composition

Their convergence across decades and problem domains is evidence that
these properties capture something fundamental about composable
computation.

Interfaces first, always. Hermeticity enables everything.
