---
description: Prioritize delivery over perfection - get it working and shipped
---

# Ship It Mode

Get $ARGUMENTS working now. Quality later. Document everything.

## Context  
- Timestamp: !`date "+%Y-%m-%d %H:%M"`
- Mode: SHIP IT
- Urgency: !`echo "$ARGUMENTS" | grep -oE "(CRITICAL|URGENT|ASAP)" | head -1 || echo "HIGH"`
- Current status: !`git status -s | wc -l || echo "0"` uncommitted files
- Build passing: !`npm test >/dev/null 2>&1 && echo "Yes" || echo "No"`
- Deploy ready: !`test -f package.json && echo "Yes" || echo "Check manually"`

## Task

<task>Ship $ARGUMENTS immediately</task>

<principles>
- Working > Perfect
- Today > Tomorrow  
- Progress > Polish
</principles>

<conditional>
If CRITICAL urgency:
- Skip all non-essential checks
- Focus on core functionality only
- Document every shortcut taken

If existing implementation:
- Patch minimally
- Preserve working code
- Add targeted fixes only

# Scenarios:
# Hotfix: Production issue, minimal change, immediate deploy
# Deadline: Feature delivery, accept tech debt, plan cleanup
# Demo: Working prototype, hardcoded data OK
# Emergency: System down, restore service first
</conditional>

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


<error-handling>
- Build fails: Comment out problematic code
- Tests fail: Skip non-critical tests with TODO
- Type errors: Use 'any' with FIXME comment
- Import errors: Copy code directly if needed
</error-handling>

<phases>
1. **Triage** - Identify minimum viable fix
2. **Execute** - Implement fastest solution  
3. **Document** - Record all shortcuts
4. **Plan** - Create cleanup TODO
</phases>

# Log format: See process step 2 above

Ship mode is emergency medicine - it saves the patient but requires rehabilitation.