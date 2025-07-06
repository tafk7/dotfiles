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

<variations>
- **Bugs**: Add reproduction steps, error messages
- **Features**: Add user stories, acceptance criteria  
- **Refactoring**: Add migration plan
- **Tech Debt**: Add how incurred, remediation
</variations>

Focus on capturing everything needed to resume work in the future.