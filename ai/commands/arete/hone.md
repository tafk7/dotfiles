---
description: Find and remove dead code
---

# /hone

<instructions>
Analyze code for dead weight, redundancy, and artifacts to polish for release.
</instructions>

<approach>
Phase 1 - Scan: Find dead code, unused exports, and temporary artifacts
Phase 2 - Analyze: Identify duplicate implementations and assess removal safety
Phase 3 - Report: Generate prioritized cleanup plan with risk levels
Priority: Safe deletions first, then duplicates, then risky removals
Output: Create cleanup analysis in _artifacts/analyses/. Log debt paid to devlog.
</approach>

<context>
Target: $ARGUMENTS
</context>