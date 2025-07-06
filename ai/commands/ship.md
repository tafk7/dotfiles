---
description: Prioritize delivery over perfection - get it working and shipped
---

# Ship It Mode

Get $ARGUMENTS working now. Quality later. Document everything.

## Context
- Timestamp: !`date "+%Y-%m-%d %H:%M"`
- Mode: SHIP IT

## Task

<task>Ship $ARGUMENTS immediately</task>

<principles>
- Working > Perfect
- Today > Tomorrow  
- Progress > Polish
</principles>

<process>
1. **Make it work**
   - Fastest path wins
   - Copy-paste OK, hard-code OK
   - One test minimum
   - Critical errors only

2. **Document shortcuts** in `artifacts/devlog_YYMM.md`:
   ```markdown
   ## SHIP MODE: [Task] - YYYY-MM-DD HH:MM
   Why: [Urgent reason]
   Shortcuts: [What corners cut]
   Cleanup: TODO-YYYY-NNN_[description].md
   ```

3. **Create redemption issue** `artifacts/issues/TODO-YYYY-NNN_[description].md`:
   ```markdown
   # Cleanup: [Description]
   
   ## Shortcuts Taken
   - [Each compromise]
   
   ## Path to Quality
   - [Steps to reach proper implementation]
   
   ## Acceptance Criteria
   - [ ] [Specific improvements needed]
   ```
</process>

<output>
Working code + documented shortcuts + redemption plan

Ship mode is an emergency escape hatch, not normal development.
</output>