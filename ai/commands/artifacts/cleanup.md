---
description: Remove old artifacts while preserving issues and context
---

# Artifacts Cleanup

Remove stale artifacts while preserving important persistent files.

## Context
- Current date: !`date +%Y-%m-%d`
- Cleanup threshold: 30 days
- Protected: issues/, context/, current devlog
- Candidates: !`find artifacts -type f -mtime +30 2>/dev/null | grep -v -E "(issues/|context/|devlog_)" | wc -l || echo "0"`

## Task

<task>Clean up artifacts older than 30 days</task>

<requirements>
1. Identify cleanup candidates (30+ days old)
2. Check for references in issues, devlog, git
3. Warn about READY_ files and large files
4. Execute removal after confirmation
5. Log cleanup operation
</requirements>

<rules>
**Preserve:**
- issues/ and context/ (permanent)
- Current/previous month devlogs
- Files with BLOCKED_ prefix
- Recently modified (<7 days)

**Warn about:**
- READY_ files not promoted
- Files >1MB
- Files referenced in issues

**Remove:**
- 30+ days old
- No active references
- Not specially marked
</rules>

<output>
```
========================================
        ARTIFACTS CLEANUP SUMMARY
========================================
Date: YYYY-MM-DD

## Cleanup Analysis
Total candidates: N files (X MB)
Protected: N files
Warnings: N items

## Warnings
[!] READY_auth.md not promoted (45 days)
[!] payment.svg referenced in TODO-2024-032

## Safe to Remove
- Old analyses: N files
- Abandoned sketches: N files
- Superseded designs: N files

## Action Summary
> Remove: N files (X MB)
> Preserve: N files
> Free: X MB

Proceed? (yes/no):
```

After confirmation:
1. Log operation in devlog
2. Remove approved files
3. Show completion summary
</output>

Use --dry-run flag to preview without removing.