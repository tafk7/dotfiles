---
description: Remove old artifacts while preserving issues and context
allowed-tools: ash(find:*), Bash(rm:*), Bash(ls:*), Bash(git:*), ReadFile
---

# Artifacts Cleanup

Remove stale artifacts while preserving important persistent files.

## Context
- Current date: !`date +%Y-%m-%d`
- Cleanup threshold: 30 days
- Protected paths: issues/, context/, current devlog
- Candidates: !`find artifacts -type f -mtime +30 2>/dev/null | grep -v -E "(issues/|context/|devlog_)" | wc -l || echo "0"`
- Mode: $ARGUMENTS (use --dry-run for preview only)

## Your Task

### 1. **Analyze Cleanup Candidates**

Identify artifacts eligible for removal:
- Age > 30 days
- Not in protected paths (issues/, context/)
- Not current/previous month devlog
- Not marked BLOCKED_

For each candidate, check:
- Git history for recent references
- Open issues for mentions
- Devlog for references
- READY_ prefix (needs promotion warning)

### 2. **Present Cleanup Summary**

Show a concise, actionable summary:

```markdown
========================================
        ARTIFACTS CLEANUP SUMMARY
========================================
Date: YYYY-MM-DD

## Cleanup Analysis
Total candidates: N files (X MB)
Protected items: N files preserved
Warnings found: N items need attention

## By Category
Analyses:  N files, oldest: YYMMDD (N days)
Sketches:  N files, oldest: YYMMDD (N days)
Designs:   N files, oldest: YYMMDD (N days)
Other:     N files

## Warnings
[!] READY_auth.md is marked ready but not promoted (45 days old)
[!] payment_flow.svg referenced in TODO-2024-032
[*] Large file: data_dump.json (5.2 MB)

## Safe to Remove
The following can be safely deleted:
- Old analyses: N files from before YYYY-MM-DD
- Abandoned sketches: N explorations never elevated
- Superseded designs: N files with newer versions
- Deprecated items: N explicitly marked

## Action Summary
> Remove: N files (X MB)
> Preserve: N files (warnings above)
> Total freed: X MB

Proceed with cleanup? (yes/no):
```

### 3. **Execute Cleanup**

If `--dry-run` specified: Show what would be removed and exit.

Otherwise, after user confirms "yes":

1. **Log the operation** in devlog:
   ```markdown
   ## YYYY-MM-DD HH:MM - CLEANUP

   **Removed**: N files (X MB)
   - Old analyses: N
   - Abandoned sketches: N
   - Superseded designs: N
   - Deprecated files: N

   **Preserved**: N files with warnings
   **Space reclaimed**: X MB
   ```

2. **Remove approved files** using git-aware deletion
3. **Show completion summary**:
   ```
   Cleanup complete:
   - Removed: N files
   - Freed: X MB
   - Preserved: N protected items

   Next actions:
   > Promote ready files: /artifacts:promote READY_auth.md
   > Review old issues: N issues > 60 days old
   ```

### 4. **Smart Cleanup Rules**

The cleanup process automatically:

**Preserves:**
- All files in issues/ and context/ (permanent)
- Current and previous month devlogs
- Files modified within 7 days (safety buffer)
- Files with BLOCKED_ prefix
- Files currently staged in git

**Warns about:**
- READY_ files not yet promoted
- Files larger than 1MB
- Files referenced in open issues
- Files mentioned in recent commits

**Only removes:**
- Files older than 30 days
- No active references found
- Not marked with special status
- Safe to delete

### Remember

This command embodies the Axiom of Deletion: "Less code is better code" extends to our workspace. But we preserve what has ongoing value:

- Issues track commitments
- Context maintains knowledge
- Recent work might still be relevant

The goal: A clean workspace that maintains necessary history while preventing sprawl.

Use `--dry-run` flag to preview without removing anything.
