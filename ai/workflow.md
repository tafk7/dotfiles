# workflow.md - Development Workflow

## Directory Structure

```
project/
├── artifacts/               # Temporary development work
│   ├── devlog_YYMM.md       # Monthly development log
│   ├── issues/              # TODO tracking with full context
│   ├── analyses/            # Code analyses (human-facing)
│   ├── designs/             # Architecture proposals
│   ├── sketches/            # Quick experiments
│   ├── context/             # AI reference (permanent)
│   ├── tests/               # Experimental tests
│   └── output/              # Generated artifacts
├── src/                     # Production code
├── tests/                   # Production tests
└── docs/                    # Permanent documentation
```

## Core Principles

### Temporal Artifacts
Everything in `artifacts/` is temporary experimentation toward The Sublime. Production code lives in `src/`, `tests/`, and `docs/`.

### Timestamp Convention
All artifact files use: `YYMMDD_HHMM_description.ext`
- Example: `241215_1430_auth_refactoring.md`
- Optional status markers: `WIP_`, `READY_`, `BLOCKED_`, `DEPRECATED_`

### Development Log
Track progress in `artifacts/devlog_YYMM.md`:
- Daily entries with task, impact, and artifacts created
- Clara adds milestones for significant achievements
- Links to issues created and code promoted

### Issue Tracking
Deferred work goes in `artifacts/issues/TODO-YYYY-NNN_description.md`:
- Full context to resume work later
- Current state, desired state, and implementation notes
- References to related artifacts and code
- Status: Open → In Progress → Resolved/Cancelled

### Context Files
Permanent AI reference in `artifacts/context/`:
- Precise definitions tied to project edicts
- Implementation mappings to actual code
- Never deleted, always kept current

## Artifact Lifecycle

**Create** → **Develop** → **Promote** → **Clean**

1. Create with timestamp in appropriate subdirectory
2. Iterate and refine during development
3. Promote to production when ready:
   - Documentation → Copy to `docs/`
   - Code → Integrate into `src/` with proper imports
4. Clean up stale artifacts periodically

## Integration with The Sublime

This workflow serves The Sublime by:
- **Encouraging experimentation** in isolated artifacts
- **Maintaining quality gates** at promotion boundaries
- **Preserving context** for long-term understanding
- **Tracking real progress** through honest devlog entries
- **Enabling continuous improvement** via issue tracking

The artifacts directory is a laboratory where we experiment freely, fail safely, and promote only what achieves The Sublime.

---

For detailed commands and templates, see the slash command reference.
