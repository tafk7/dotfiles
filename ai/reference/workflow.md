# workflow.md - Artifacts Development Process

This document defines the _artifacts directory structure and key conventions.

## Directory Structure

```
_artifacts/           # Experimental workspace
├── issues/         # TODO tracking
├── analyses/       # Analysis outputs
├── designs/        # Architecture documents
├── sketches/       # Experimental code
├── reference/      # Permanent references (never delete)
└── checklists/     # Task lists

src/                # Production code
tests/              # Production tests  
docs/               # Permanent documentation
```

## Non-Obvious Conventions

### Status Prefixes
- `READY_` - Artifact ready for production promotion
- `BLOCKED_` - Work blocked by dependencies
- No prefix - Work in progress

### TODO Format
Issues must follow: `TODO-YYMM-NNN_description.md`
- YYMM: Year-month (e.g., 2412 for December 2024)
- NNN: Sequential number within that month
- Underscores in description, not hyphens

### Preservation Rules
Never delete or move:
- `_artifacts/reference/` - Permanent project references
- Any `BLOCKED_*` files - May unblock later

## Quality Gates for READY_ Status

Before applying READY_ prefix:
- Functionality verified
- Tests written and passing
- Aligns with project edicts
- Self-contained (no external dependencies)

Arete.