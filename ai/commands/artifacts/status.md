---
description: Show current artifacts, open issues, and recent activity
---

# Artifacts Status

Display comprehensive status of artifacts directory including active work and open issues.

## Context
- Artifacts exist: !`test -d artifacts && echo "Yes" || echo "No"`
- Last cleanup: !`git log --grep="CLEANUP" -n 1 --format="%cd" --date=short -- artifacts/devlog*.md 2>/dev/null || echo "Never"`

## Task

<task>Generate artifacts status report</task>

<requirements>
1. Analyze artifacts directory comprehensively
2. Identify open issues and their priority
3. Detect files ready for promotion
4. Flag potential problems (orphaned, duplicates)
5. Provide actionable next steps
</requirements>

<output>
```
========================================
        ARTIFACTS STATUS REPORT
========================================
Generated: YYYY-MM-DD HH:MM

## Overview
Total: N | Open issues: N | Storage: X MB
Last cleanup: YYYY-MM-DD | Last promotion: YYYY-MM-DD

## Active Work
### Current Development
- Devlog: artifacts/devlog_YYMM.md (N entries)
- Last: YYYY-MM-DD - [Subject]

### Open Issues (N)
HIGH PRIORITY
> TODO-YYYY-NNN: [Description] (blocked N days)

STANDARD
- TODO-YYYY-NNN: [Description] (N days)

TECHNICAL DEBT
- TODO-YYYY-NNN: [Ship mode cleanup] (N days)

## Artifact Analysis
< 7 days:  [===========] N files
7-30 days: [=====      ] N files
> 30 days: [==         ] N files (cleanup candidates)

## Ready for Production
[!] READY_filename.ext -> src/module/file.ext
[!] mentioned_in_devlog.js -> Ready since YYYY-MM-DD

## Detected Issues
* Orphaned: filename.ext (no references)
* Duplicate: explore_auth.js, explore_authentication.py

## Quick Actions
> Promote: /artifacts/promote READY_filename.ext
> Cleanup: /artifacts/cleanup (N candidates)
> Review: TODO-YYYY-NNN (blocked)
```
</output>

<indicators>
- `[!]` = Action needed
- `*` = Potential issue
- `>` = High priority
- `-` = Standard item
</indicators>

Provide visibility into work status and clear next steps.