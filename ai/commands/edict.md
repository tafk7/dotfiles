---
description: Check project edict compliance
---

# Check Edicts

Check if $ARGUMENTS (or current directory) violates any project edicts (constraints).

## Task

<task>Verify edict compliance for $ARGUMENTS</task>

<requirements>
1. Parse edicts from CLAUDE.md (exit if missing)
2. Check compliance for all edict categories
3. Generate actionable violation report
</requirements>

<phases>
1. **Parse** - Extract edicts from CLAUDE.md
2. **Check** - Verify compliance
3. **Report** - Document violations and fixes
</phases>

<output>
artifacts/analyses/YYMMDD_HHMM_edict_compliance.md
</output>

<conditional>
If no violations: Note full compliance
If critical violations: Mark as blocking
</conditional>

<error-handling>
Missing CLAUDE.md: Exit with setup instructions
Malformed edicts: Skip and note in report
</error-handling>

Every edict expires eventually - compliance today, freedom tomorrow.