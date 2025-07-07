---
description: Incremental improvement recommendations with checklist
---

# /refine

Analyze $ARGUMENTS and provide incremental improvement recommendations with implementation checklist.

## Task

<task>Analyze and recommend incremental improvements for $ARGUMENTS</task>

<requirements>
1. Identify 3-5 improvements balancing impact vs risk
2. Provide clear implementation steps for each
3. Create actionable checklist for developer
4. Include rollback strategies
</requirements>

<phases>
1. **Analyze** - Code quality assessment
2. **Prioritize** - By impact/risk ratio
3. **Document** - Actionable checklist
</phases>

<output>
artifacts/checklists/YYMMDD_HHMM_refine_checklist.md
</output>

<template>
# Refinement Checklist: [Target]

## Quick Wins (< 30min)
- [ ] **[Improvement]**: [What and where]
  - Impact: [Why this matters]
  - Steps: [How to implement]

## High Impact (1-2h)
- [ ] **[Improvement]**: [What and where]
  - Current: [Problem]
  - Proposed: [Solution]
  - Rollback: [If needed]

## Summary
- Total effort: ~[X] hours
- Expected impact: [Key benefits]
</template>

<conditional>
If tests exist: Include test validation
If no tests: Prioritize test creation
If complex: Focus on simplification
</conditional>

<error-handling>
Target unclear: Ask for specific area
Too broad: Suggest smaller scope
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: Current directory
# - path: Specific file/directory
# - --focus [area]: Refinement focus

Better code through thoughtful, incremental change.