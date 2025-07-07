---
description: Generate actionable implementation checklist from plans
---

# /checklist

Create step-by-step implementation checklist from $ARGUMENTS or current conversation.

## Task

<task>Generate actionable checklist from $ARGUMENTS</task>

<requirements>
1. Parse plan from file path or current conversation
2. Break into concrete, executable steps
3. Group into logical phases with time estimates
4. Include verification steps
5. Add specific commands and file paths
</requirements>

<phases>
Parse → Extract Tasks → Organize Phases → Add Verification → Output
</phases>

<output>
artifacts/checklists/YYMMDD_HHMM_checklist_[description].md
</output>

<conditional>
If path provided: Read plan from file
If no path: Use current conversation
If no plan found: Error with suggestions
</conditional>

<error-handling>
No plan: Suggest /architect or /refine first
File not found: List available plans
</error-handling>

Plans without steps are merely wishes.