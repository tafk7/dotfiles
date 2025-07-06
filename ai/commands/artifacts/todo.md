---
description: Create comprehensive issue file with full context
---

# Create TODO

Generate issue for: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Next ID: !`ls artifacts/issues/TODO-*.md 2>/dev/null | wc -l | xargs -I {} expr {} + 1 || echo "1"`
- Year: !`date "+%Y"`

## Task

<task>Create TODO issue for: $ARGUMENTS</task>

<requirements>
1. Generate `artifacts/issues/TODO-YYYY-NNN_description.md`
2. Include full context for future resumption
3. Add clear success criteria and implementation steps
4. Log creation in devlog
</requirements>

<phases>
1. **Parse** - Extract priority and effort from $ARGUMENTS
2. **Generate** - Create issue file with unique ID
3. **Document** - Add comprehensive context
4. **Log** - Update devlog with creation
</phases>

<conditional>
Parse priority from $ARGUMENTS:
- "P0" or "blocking" → P0 with urgency context
- "bug" → Add reproduction steps, error messages, test links
- Effort: defaults to Medium if unspecified
</conditional>

<template>
```markdown
# $ARGUMENTS

**Created**: YYYY-MM-DD HH:MM
**Status**: Open
**Priority**: [P0: Blocking | P1: Important | P2: Enhancement]
**Effort**: [Small: <2hr | Medium: 2-8hr | Large: >1 day]

## Context
[Why this exists, how discovered, devlog/PR links]

## Current State
[What exists now - file paths, code snippets]
[What's broken or missing]

## Desired State
[Success criteria]
[Example of desired behavior]

## How to Start
1. Read: [files to review]
2. Run: [commands to reproduce]
3. Check: artifacts/context/[relevant].md

## Implementation Notes
- [Technical approach]
- [Constraints or gotchas]

## Checklist
- [ ] [Implementation steps]
- [ ] Tests added
- [ ] Documentation updated
- [ ] Devlog entry created

## References
- Related: [TODO-NNN, PR#]
- Artifacts: [sketches, analyses]
```
</template>

# Type-specific sections added automatically:
# - Bugs: reproduction steps, error messages
# - Features: user stories, acceptance criteria
# - Refactoring: migration plan
# - Tech Debt: how incurred, remediation path

<error-handling>
- Duplicate ID: Increment and retry
- Missing context: Gather from git history
- Invalid priority: Default to P1
- Long description: Truncate filename, keep full in content
</error-handling>

Comprehensive context today prevents confusion tomorrow - capture everything.