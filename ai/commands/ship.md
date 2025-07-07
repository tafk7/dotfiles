---
description: Prioritize delivery over perfection - get it working and shipped
---

# Ship It Mode

Get $ARGUMENTS working now. Quality later. Document everything.

## Context  
- Timestamp: !`date "+%Y-%m-%d %H:%M"`
- Mode: SHIP IT
- Urgency: !`echo "$ARGUMENTS" | grep -oE -m1 "(CRITICAL|URGENT|ASAP)" || echo "HIGH"`
- Current status: !`git status -s | wc -l` uncommitted files
- Build passing: !`npm test >/dev/null 2>&1 && echo "Yes" || echo "No"`
- Deploy ready: !`test -f package.json && echo "Yes" || echo "Check manually"`

## Task

<task>Ship $ARGUMENTS immediately</task>

<requirements>
1. Get core functionality working with fastest path
2. Document all shortcuts taken in devlog
3. Create cleanup TODO issue for tech debt
4. One test minimum to verify critical path
</requirements>

<phases>
1. **Triage** - Identify minimum viable fix
2. **Execute** - Implement fastest solution  
3. **Document** - Record all shortcuts
4. **Plan** - Create cleanup TODO
</phases>

<output>
Devlog entry in `artifacts/devlog_YYMM.md`:
```markdown
## SHIP MODE: [Task] - YYYY-MM-DD HH:MM
Why: [Urgent reason]
Shortcuts: [What corners cut]
Cleanup: TODO-YYMM-NNN_[description].md
```

Redemption issue `artifacts/issues/TODO-YYMM-NNN_[description].md`:
```markdown
# Cleanup: [Description]

## Shortcuts Taken
- [Each compromise]

## Path to Quality
- [Steps to reach proper implementation]

## Acceptance Criteria
- [ ] [Specific improvements needed]
```
</output>

<conditional>
If CRITICAL: Skip checks, core functionality only, document shortcuts | If existing: Patch minimally, preserve working code
Scenarios: Hotfix(prod issue, minimal) | Deadline(tech debt OK) | Demo(prototype, hardcode OK) | Emergency(restore first)
</conditional>

<error-handling>
- Build fails: Comment out problematic code
- Tests fail: Skip non-critical tests with TODO
- Type errors: Use 'any' with FIXME comment
- Import errors: Copy code directly if needed
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - Task description with optional urgency markers
# - CRITICAL/URGENT/ASAP: Triggers maximum speed mode
# - Feature/fix descriptions: Standard ship mode

Ship mode is emergency medicine - it saves the patient but requires rehabilitation.