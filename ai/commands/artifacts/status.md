---
descrption: Show current artifacts, open issues, and recent activity
allowed-tools: Bash(find:*), Bash(ls:*), Bash(head:*), Bash(tail:*), Bash(wc:*), Bash(git:*)
---

# Artifacts Status

Display comprehensive status of artifacts directory including active work and open issues.

## Context
- Current directory: !`pwd`
- Artifacts directory exists: !`test -d artifacts && echo "Yes" || echo "No"`
- Last cleanup: !`git log --grep="CLEANUP" -n 1 --format="%cd" --date=short -- artifacts/devlog*.md 2>/dev/null || echo "Never"`
- Last promotion: !`git log --grep="PROMOTED" -n 1 --format="%cd" --date=short -- artifacts/devlog*.md 2>/dev/null || echo "Never"`

## Your Task

### 1. **Analyze Artifacts Comprehensively**

Scan the artifacts directory to gather:
- File counts, ages, and sizes
- Issue status and priorities
- Recent devlog activity
- Git history for promotions and cleanups
- File references and dependencies

Generate a concise, actionable status report that helps maintain momentum toward The Sublime.

### 2. **Generate Status Report**

Provide a concise status with progressive detail:

```markdown
========================================
        ARTIFACTS STATUS REPORT
========================================
Generated: YYYY-MM-DD HH:MM

## Overview
Total artifacts: N | Open issues: N | Storage: X MB
Last cleanup: YYYY-MM-DD | Last promotion: YYYY-MM-DD

## Active Work
### Current Development
- Devlog: artifacts/devlog_YYMM.md (N entries, N milestones)
- Last entry: YYYY-MM-DD - [Subject]

### Open Issues (N)
HIGH PRIORITY
> TODO-YYYY-NNN: [Description] (blocked N days)

STANDARD
- TODO-YYYY-NNN: [Description] (age: N days)
- TODO-YYYY-NNN: [Description] (age: N days)

TECHNICAL DEBT (from ship mode)
- TODO-YYYY-NNN: [Cleanup needed for: feature] (age: N days)

## Artifact Analysis
### By Age and Activity
< 7 days:  [===========] N files (active)
7-30 days: [=====      ] N files (recent)
> 30 days: [==         ] N files (cleanup candidates)

### By Type
- analyses:  N files (latest: YYMMDD_topic)
- sketches:  N files (N elevated to production)
- designs:   N files
- context:   N files (permanent)

### Ready for Production
[!] READY_filename.ext -> Suggested: src/module/file.ext
[!] mentioned_in_devlog.js -> Marked ready on YYYY-MM-DD

## Detected Issues
* Orphaned: filename.ext (no references found)
* Duplicate exploration: explore_auth.js, explore_authentication.py
* Stale branch reference: feature_xyz.md (branch deleted)

## Quick Actions
> Promote ready files:  /artifacts:promote READY_filename.ext
> Clean old artifacts:  /artifacts:cleanup (N candidates)
> Review blocked work:  See TODO-YYYY-NNN

---
Run with --verbose for detailed file listings
```

### 3. **Implementation Details**

**For Issues:**
- Parse TODO files for age (days since creation)
- Identify blocked items (age > 14 days = blocked)
- Separate ship mode debt from regular issues
- Flag HIGH PRIORITY with ">" prefix

**For Activity Visualization:**
- Use simple ASCII progress bars [====    ]
- Show proportional fill based on counts
- Keep bars consistent width (10-15 chars)

**For Smart Detection:**
- Check git log for file references
- Identify files with no imports/references
- Find similar named explorations
- Detect references to deleted branches/files

**Status Indicators:**
- `[!]` = Action needed (ready for promotion)
- `*` = Potential issue (orphaned, duplicate)
- `>` = High priority or recommended action
- `-` = Standard item

### 4. **Output Modes**

**Default Mode** (shown above):
- Concise overview with key metrics
- Actionable items highlighted
- Clear next steps

**Verbose Mode** (with --verbose flag):
- Full file listings with timestamps
- Detailed issue descriptions
- Complete devlog entry previews
- All detected anomalies explained

### 5. **The Goal**

This command supports The Sublime by providing:
- **Visibility**: No hidden debt or forgotten work
- **Actionability**: Clear next steps, not just data
- **Intelligence**: Smart detection of issues
- **Efficiency**: Progressive detail levels

The status should answer:
- What am I actively working on?
- What's ready to ship?
- What's accumulating as debt?
- What needs immediate attention?

Clean workspace, clear mind, sublime code.
