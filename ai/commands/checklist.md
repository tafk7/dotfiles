---
description: Generate actionable implementation checklist from plans
---

# /checklist

Create step-by-step implementation checklist from $ARGUMENTS or current conversation.

## Task

<task>Generate actionable checklist from $ARGUMENTS</task>

<requirements>
1. Break plan into concrete, executable steps
2. Group into logical phases with time estimates
3. Include verification steps where needed
</requirements>

<phases>
1. **Extract** - Identify tasks from plan
2. **Organize** - Group into phases
3. **Detail** - Add specifics and verification
</phases>

<output>
artifacts/checklists/YYMMDD_HHMM_checklist_[description].md
</output>

<conditional>
If path provided: Read plan from file
If no path: Use current conversation
</conditional>

<error-handling>
No plan found: Suggest creating one first
File not found: List available plans
</error-handling>

Plans without steps are merely wishes.