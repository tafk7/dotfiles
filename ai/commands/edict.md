---
description: Check project edict compliance
---

# Check Edicts

Check if $ARGUMENTS (or current directory) violates any project edicts (constraints).

## Context
- Target: !`echo "${ARGUMENTS:-current directory}"`
- Project config: !`test -f CLAUDE.md && echo "Found" || echo "Not found"`
- Active edicts: !`grep -c "^### Edict\." CLAUDE.md 2>/dev/null || echo "0"`

## Task

<task>Verify edict compliance for $ARGUMENTS</task>

<requirements>
1. Parse edicts from CLAUDE.md (exit if missing)
2. Check compliance: Compatibility, Performance, Security, Dependencies, Architecture  
3. Categorize findings and generate actionable report
</requirements>

<phases>
1. **Parse** - Extract edicts | 2. **Check** - Verify compliance
3. **Analyze** - Categorize findings | 4. **Report** - Generate output
</phases>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_edict_compliance.md`:

```markdown
# Edict Compliance Report  
Target: [checked] | Date: YYYY-MM-DD HH:MM
✅ Compliant: N | ❌ Violations: N | ⚠️ Warnings: N

## ❌ VIOLATIONS
### Edict.Category.N
Violated: [constraint] | Found: [violation] | Location: file:line | Fix: [change]

## Actions Required
[Priority fixes and next steps]
```
</output>

<conditional>
No violations: Highlight compliance, suggest removal candidates | Critical: Mark ❌ CRITICAL, immediate fixes, block ops
Errors: Missing CLAUDE.md(exit), Malformed(skip), Access denied(note), Large codebase(sample)
Modes: Quick(summary), Full(detailed), CI(parseable), Redemption(progress)
</conditional>

<error-handling>
Missing CLAUDE.md: Exit with clear message about requirements
Malformed edicts: Skip invalid sections, note in report
Access denied: Document accessible files only
Parse errors: Graceful degradation with partial results
</error-handling>

Every edict expires eventually - compliance today, freedom tomorrow.