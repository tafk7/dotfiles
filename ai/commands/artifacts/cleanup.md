---
description: Remove old artifacts while preserving issues and context
---

# Artifacts Cleanup

Clean up: $ARGUMENTS

## Context
- Current date: !`date +%Y-%m-%d`
- Threshold: !`echo "${ARGUMENTS:-30}" | grep -o '[0-9]\+' | head -1 || echo "30"` days
- Mode: !`[[ "$ARGUMENTS" == *"--dry-run"* ]] && echo "DRY RUN" || echo "EXECUTE"`
- Protected: issues/, reference/, current devlog
- Candidates: !`days=$(echo "${ARGUMENTS:-30}" | grep -o '[0-9]\+' | head -1 || echo "30"); find artifacts -type f -mtime +$days 2>/dev/null | grep -v -E "(issues/|reference/|devlog_)" | wc -l || echo "0"`
- Total size: !`days=$(echo "${ARGUMENTS:-30}" | grep -o '[0-9]\+' | head -1 || echo "30"); find artifacts -type f -mtime +$days 2>/dev/null | grep -v -E "(issues/|reference/|devlog_)" -exec du -ch {} + | tail -1 | cut -f1 || echo "0"`

## Task

<task>Clean up artifacts older than specified threshold</task>

<requirements>
1. Identify cleanup candidates
2. Check for references in issues, devlog, git
3. Warn about READY_ files and large files
4. Execute removal after confirmation
5. Log cleanup operation
</requirements>

<rules>
**Preserve:** issues/, reference/, current devlog, BLOCKED_ files, <7 days old
**Warn:** READY_ files, >1MB files, referenced in issues
**Remove:** Old files without special markers
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

<conditional>
If --dry-run specified:
- Show analysis only
- No files removed
- Clear preview marking

If file count > 50:
- Group by type
- Show size totals
- Batch confirmation
</conditional>

# Argument handling:
# - No args: 30-day default
# - Number: Custom threshold (e.g., "14")
# - --dry-run: Preview only
# - Combinations: "--dry-run 7"

Clean artifacts, free mind. Every byte reclaimed fuels future creation.