---
descrption: Log development progress with automatic milestone detection
---

# Log Progress

Record: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Branch: !`git branch --show-current 2>/dev/null || echo "main"`
- Open TODOs: !`find artifacts/issues -name "TODO-*.md" 2>/dev/null | wc -l || echo "0"`

## Your Task

Add entry to `artifacts/devlog_YYMM.md`:

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

For major achievements (>30% improvement), add milestone:
```markdown
---
=== MILESTONE: [Achievement] ===
[One line explaining significance]
===
---
```

Auto-link artifacts from last hour. Update referenced issue status.

Record real impact, not aspirations.
