---
description: Create comprehensive issue file with full context
---

# Create TODO

Generate issue for: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Next ID: !`ls artifacts/issues/TODO-*.md 2>/dev/null | wc -l | xargs -I {} expr {} + 1 || echo "1"`
- Year: !`date "+%y"`

## Task

<task>Create TODO issue for: $ARGUMENTS</task>

<requirements>
1. Generate `artifacts/issues/TODO-YYMM-NNN_description.md`
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

<template>
```markdown
# $ARGUMENTS

**Created**: YYYY-MM-DD HH:MM | **Status**: Open
**Priority**: [P0: Blocking | P1: Important | P2: Enhancement]  
**Effort**: [Small: <2hr | Medium: 2-8hr | Large: >1 day]

## Context & Current State
[Why this exists, what's broken/missing, file paths]

## Desired State & Success Criteria
[Goals, examples, acceptance criteria]

## How to Start
1. Read: [files] | 2. Run: [commands] | 3. Check: artifacts/context/

## Implementation
- Technical approach | Constraints | Gotchas
- [ ] Implementation steps | [ ] Tests | [ ] Docs | [ ] Devlog

## References
Related: [TODO-YYMM-NNN] | Artifacts: [sketches, analyses]
```
</template>

<conditional>
Parse: P0/blocking→urgency, bug→reproduction, default effort Medium | Types: Bug/Feature/Refactor/TechDebt auto-sections
Errors: Duplicate ID(increment), Missing context(git history), Invalid priority(P1 default)
</conditional>

Comprehensive context today prevents confusion tomorrow - capture everything.