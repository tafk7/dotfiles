---
description: Prioritize delivery over perfection - get it working and shipped
---

# Ship It Mode

Get $ARGUMENTS working now. Quality later. Document everything.

## Context
- Urgency: !`echo "$ARGUMENTS" | grep -oE -m1 "(CRITICAL|URGENT|ASAP)" || echo "HIGH"`

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
3. **Document** - Record shortcuts and create cleanup TODO
</phases>

<output>
artifacts/devlog_YYMM.md (append entry)
artifacts/issues/TODO-YYMM-NNN_[description].md
</output>

<conditional>
If CRITICAL: Skip checks, core functionality only
</conditional>

<error-handling>
Build fails: Comment out problematic code
Tests fail: Skip non-critical with TODO
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - Task description with optional urgency markers
# - CRITICAL/URGENT/ASAP: Triggers maximum speed mode

Ship mode is emergency medicine - it saves the patient but requires rehabilitation.