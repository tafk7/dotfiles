---
description: Show current artifacts, open issues, and recent activity
---

# Artifacts Status  

Display comprehensive status of artifacts directory including active work and open issues.

Filter: $ARGUMENTS (e.g., "issues", "ready", "old", or file pattern)

## Context
- Artifacts exist: !`test -d artifacts && echo "Yes" || echo "No"`
- Filter: !`echo "${ARGUMENTS:-all}"`
- Last cleanup: !`git log --grep="CLEANUP" -n 1 --format="%cd" --date=short -- artifacts/devlog*.md 2>/dev/null || echo "Never"`
- Storage used: !`du -sh artifacts 2>/dev/null | cut -f1 || echo "0"`

## Task

<task>Generate artifacts status report${ARGUMENTS:+ for: $ARGUMENTS}</task>

<requirements>
1. Analyze artifacts directory comprehensively
2. Identify open issues and their priority
3. Detect files ready for promotion
4. Flag potential problems (orphaned, duplicates)
5. Provide actionable next steps
</requirements>

<phases>
1. **Scan** - Inventory all artifacts
2. **Analyze** - Categorize and assess
3. **Report** - Generate structured output
4. **Recommend** - Suggest next actions
</phases>

<output>
```
ARTIFACTS STATUS - YYYY-MM-DD HH:MM
Total: N files | Issues: N open | Storage: X MB

## Active Work
Devlog: devlog_YYMM.md - [Last entry subject]
Issues: N high priority, N standard, N tech debt

## Files by Age
Recent (<7d): N files
Active (7-30d): N files  
Stale (>30d): N files [cleanup candidates]

## Action Items
! READY_file.ext → production path
! TODO-YYMM-NNN: [High priority issue]
* N orphaned files detected
* N cleanup candidates

Quick: /promote READY_file | /cleanup N files | /todo review
```
</output>

# Indicators: [!] Action needed, * Potential issue, > High priority

# Filter behaviors:
# - "issues": Show only TODO files grouped by priority with age/blockers
# - "ready": Show READY_ files with destination paths and promotion readiness
# - "old": Show cleanup candidates with space savings
# - Team mode: Include author attribution
# - Summary mode: High-level counts only

<error-handling>
Missing artifacts directory: Create empty directory and report
No matching files: Display helpful message with examples
Permission denied: Show accessible files only
Large artifact count: Paginate or summarize results
</error-handling>

Clear visibility enables decisive action - status illuminates the path forward.