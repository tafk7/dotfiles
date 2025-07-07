---
description: Create comprehensive issue file with full context
---

# Create TODO

Generate issue for: $ARGUMENTS

## Task

<task>Create TODO issue for: $ARGUMENTS</task>

<requirements>
1. Generate artifacts/issues/TODO-YYMM-NNN_description.md
2. Include full context for future resumption
3. Add clear success criteria and implementation steps
</requirements>

<phases>
1. **Parse** - Extract priority and type from request
2. **Generate** - Create issue with unique ID
</phases>

<output>
artifacts/issues/TODO-YYMM-NNN_description.md
</output>

<template>
# $ARGUMENTS

**Created**: YYYY-MM-DD HH:MM | **Status**: Open
**Priority**: [P0/P1/P2] | **Effort**: [Small/Medium/Large]

## Context
[Current state and why this matters]

## Success Criteria
[What done looks like]

## Implementation
[Approach and key steps]
</template>

<error-handling>
Missing issues directory: Create automatically
Empty arguments: Prompt for description
</error-handling>

Comprehensive context today prevents confusion tomorrow - capture everything.