---
description: Check code against project edicts
---

# /edict

<instructions>
Check if code violates any project edicts (constraints) defined in CLAUDE.md.
</instructions>

<approach>
Phase 1 - Parse: Extract edicts from project CLAUDE.md file
Phase 2 - Check: Verify compliance across all edict categories
Phase 3 - Report: Document violations with suggested fixes
Priority: Critical violations that block functionality
Output: Create compliance report in artifacts/analyses/
</approach>

<context>
Target: $ARGUMENTS
</context>