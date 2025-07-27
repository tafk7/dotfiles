# Proposed AI-Focused workflow.md

## Current Issues
The current workflow.md mixes:
1. **User instructions** (how to invoke commands)
2. **AI guidance** (how to use artifacts)
3. **Human workflow examples** (bash command sequences)

## Proposed New Version

```markdown
# workflow.md - Artifacts Development Process

This document defines how to use the artifacts directory for experimental work and development tracking.

## Directory Structure

```
artifacts/           # Experimental workspace (your primary output location)
├── devlog.md       # Progress tracking
├── issues/         # TODO tracking (TODO-YYMM-NNN_*.md format)
├── analyses/       # Analysis outputs
├── designs/        # Architecture documents
├── sketches/       # Experimental code
├── reference/      # Permanent references (preserve these)
└── checklists/     # Task lists

src/                # Production code (promote artifacts here)
tests/              # Production tests  
docs/               # Permanent documentation
```

## Key Principles

1. **Artifacts First**: Create outputs in `artifacts/` subdirectories
2. **Clear Naming**: Use descriptive filenames that indicate purpose
3. **Status Tracking**: Apply prefixes to indicate state:
   - `READY_` - Ready for production
   - `BLOCKED_` - Has dependencies
4. **Never Delete**: Preserve `reference/`, `devlog.md`, and active issues

## Output Patterns

When commands specify outputs:
- "Create analysis" → `artifacts/analyses/[descriptive_name].md`
- "Create design" → `artifacts/designs/[descriptive_name].md`
- "Create checklist" → `artifacts/checklists/[descriptive_name].md`
- "Create TODO" → `artifacts/issues/TODO-YYMM-NNN_[description].md`

## Development Log

Append to `artifacts/devlog.md` when:
- Completing significant work
- Encountering blockers
- Making architectural decisions

Format:
```markdown
## Date

**Time** - Brief description
- Key outcome
- Related artifact: [filename]
```

## Issue Tracking

TODO format: `TODO-YYMM-NNN_description.md`
- YYMM: Current year-month (e.g., 2412)
- NNN: Sequential number
- Include full context for resuming work

## Quality Considerations

Before marking artifacts as READY_:
- Code functions correctly
- Tests exist and pass
- Documentation is clear
- Aligns with project constraints

## Remember

- The artifacts directory is for experimentation and iteration
- Production code requires promotion from artifacts
- Preserve work history in devlog
- Track deferred work as TODOs
```

## Key Changes

1. **Removed user-facing content**: No bash commands or slash command examples
2. **Focused on AI needs**: Where to put files, how to name them, when to use prefixes
3. **Simplified format**: Clearer, more direct instructions
4. **Maintained essential info**: Directory structure, naming conventions, quality gates
5. **Added "Output Patterns"**: Direct mapping from command instructions to file locations

This version is ~50% shorter and 100% focused on what the AI needs to know.