---
description: Log development progress with automatic milestone detection
---

# Log Progress

Record: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Branch: !`git branch --show-current 2>/dev/null || echo "main"`
- Open TODOs: !`find artifacts/issues -name "TODO-*.md" 2>/dev/null | wc -l || echo "0"`

## Task

<task>Log progress for: $ARGUMENTS</task>

<requirements>
1. Add entry to `artifacts/devlog_YYMM.md`
2. Quantify real impact (lines, performance, bugs)
3. Link artifacts created in last hour
4. Update referenced issue status
5. Add milestone marker for major achievements (>30% improvement)
</requirements>

<template>
```markdown
## YYYY-MM-DD HH:MM

**Task**: $ARGUMENTS
**Impact**: [Quantify: lines reduced, performance gained, bugs fixed]
**Artifacts**:
  - [Files created in artifacts/]
**Promoted**: [Files moved to production]
**Issues**: [Created: TODO-NNN | Resolved: TODO-NNN]

[Additional context if valuable]
```

For milestones:
```markdown
---
=== MILESTONE: [Achievement] ===
[One line explaining significance]
===
---
```
</template>

Record real impact, not aspirations.