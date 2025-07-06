---
description: Log development progress with automatic milestone detection
---

# Log Progress

Record: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Branch: !`git branch --show-current 2>/dev/null || echo "main"`
- Open TODOs: !`find artifacts/issues -name "TODO-*.md" 2>/dev/null | wc -l || echo "0"`
- Recent artifacts: !`find artifacts -type f -mmin -60 2>/dev/null | grep -v devlog | wc -l || echo "0"`
- Last commit: !`git log -1 --format="%h %s" 2>/dev/null || echo "No commits"`
- Devlog exists: !`test -f "artifacts/devlog_$(date +%y%m).md" && echo "Yes" || echo "No"`

## Task

<task>Log progress for: $ARGUMENTS</task>

<requirements>
1. Add entry to `artifacts/devlog_YYMM.md`
2. Quantify real impact (lines, performance, bugs)
3. Link artifacts created in last hour
4. Update referenced issue status
5. Add milestone marker for major achievements (>30% improvement)
</requirements>

<phases>
1. **Analyze** - Gather metrics and changes
2. **Document** - Write structured entry
3. **Link** - Connect artifacts and issues
4. **Milestone** - Mark significant achievements
</phases>

<template>
```markdown
## YYYY-MM-DD HH:MM

**Task**: $ARGUMENTS
**Impact**: [Quantify: lines reduced, performance gained, bugs fixed]
**Artifacts**: [Files created in artifacts/]
**Promoted**: [Files moved to production]
**Issues**: [Created: TODO-NNN | Resolved: TODO-NNN]

# Type-specific additions:
# Bug Fix: error message, root cause, fix
# Feature: user story, acceptance criteria
# Refactor: lines reduced, complexity metrics
# Research: questions answered, decisions made

# Milestones (>30% improvement):
# === MILESTONE: [Achievement] ===
```
</template>

<conditional>
If no devlog exists: Create with proper header
If milestone detected: Add marker and update metrics
</conditional>

<error-handling>
- Missing devlog: Create with proper header
- Invalid date: Use current timestamp
- No artifacts: Note exploration/planning phase
- Failed linking: Log anyway, fix references later
</error-handling>

Real impact compounds - every honest entry builds momentum toward perfection.