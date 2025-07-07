---
description: Analyze code for dead weight, redundancy, and artifacts to polish for release
---

# Cleanup Analysis

Post-implementation analysis of $ARGUMENTS to identify and remove technical debris.

## Task

<task>Analyze $ARGUMENTS for cleanup opportunities</task>

<requirements>
1. Identify dead code and unused exports
2. Find duplicate implementations
3. Detect temporary/development artifacts
4. Generate prioritized cleanup plan
</requirements>

<phases>
1. **Scan** - Find cleanup targets and assess safety
2. **Analyze** - Identify risks and dependencies
3. **Report** - Generate actionable plan
</phases>

<output>
artifacts/analyses/YYMMDD_HHMM_cleanup_analysis.md
</output>

<template>
# Cleanup Analysis - [Target]
Date: YYYY-MM-DD HH:MM

## Summary
Dead code: N | Duplicates: N | Artifacts: N | Size: X MB → Y MB

## 🟢 Safe to Remove
- [ ] *.tmp, *.bak files (N files, X KB)
- [ ] console.log statements (N instances)
- [ ] [Other safe deletions]

## 🟡 Review First
- [ ] UnusedFunction() - file.js:42 - No refs found
- [ ] processData() ≈ transformData() - Merge?

## 🔴 Tech Debt
- TODO: Error handling - file.js:25
- [Other debt items]
</template>

<conditional>
If production: Conservative approach
If no tests: Flag all deletions as high-risk
</conditional>

Polish reveals quality - remove the unnecessary to illuminate the essential.