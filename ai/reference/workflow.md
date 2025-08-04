# workflow.md - Artifacts Development Process

This document defines the _artifacts directory structure and key conventions.

## Directory Structure

```
_artifacts/           # Experimental workspace
├── devlog.md       # Progress tracking (append only)
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

### Development Log
Append to existing `_artifacts/devlog.md` - never create new devlog files.

Format entries with reverse chronological order (newest first):
```markdown
## YYYY-MM-DD

### HH:MM - Summary of change
- Key decision or outcome
- Related: `path/to/artifact.md`

### HH:MM - Another change
- Details
```

Start new date sections at the top of the file, not the bottom. Use horizontal separators (=== or ---) to make new days and significant milestones visually prominent.

### Preservation Rules
Never delete or move:
- `_artifacts/reference/` - Permanent project references
- `_artifacts/devlog.md` - Historical record
- Any `BLOCKED_*` files - May unblock later

## Quality Gates for READY_ Status

Before applying READY_ prefix:
- Functionality verified
- Tests written and passing
- Aligns with project edicts
- Self-contained (no external dependencies)

Arete.