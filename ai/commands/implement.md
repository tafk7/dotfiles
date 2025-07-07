---
description: Execute checklist items with real-time progress tracking
---

# /implement

Execute checklist items from $ARGUMENTS with real-time progress tracking and devlog updates.

## Context
- Target checklist: $ARGUMENTS
- Total items: !`grep -c "^- \[.\]" "$ARGUMENTS" 2>/dev/null || echo "0"`
- Remaining: !`grep -c "^- \[ \]" "$ARGUMENTS" 2>/dev/null || echo "0"`

## Task

<task>Execute checklist items from $ARGUMENTS with progress tracking</task>

<requirements>
1. Parse and execute checkbox items sequentially
2. Update checkboxes from `[ ]` to `[x]` as completed
3. Add timestamps for major milestones
4. Log implementation progress in devlog
</requirements>

<phases>
1. **Parse** - Read checklist and identify executable items
2. **Execute** - Implement items sequentially with real-time updates
3. **Track** - Update checkboxes and log progress
</phases>

<output>
Updated checklist file with progress + devlog entry
</output>

<conditional>
If phase range specified: Execute only matching phases
If errors during execution: Mark item as blocked, continue
If completed: Mark entire checklist as done with summary
</conditional>

<error-handling>
File not found: List available checklists in artifacts/
No checkboxes found: Explain checklist format requirements
Invalid phase range: Show available phases
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - checklist-path: Required path to checklist file
# - Optional: "Phase 1-3" or "Quick Wins" to limit scope
# - Optional: "--dry-run" to preview without execution

Implementation without tracking is merely motion - progress demands evidence.