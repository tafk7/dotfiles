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
1. Parse edicts from CLAUDE.md (if not found, report and exit)
2. Check target against each active edict
3. Identify violations, warnings, and expired edicts
4. Generate compliance report
</requirements>

<compliance-checks>
- **Compatibility**: API contracts, breaking changes, data formats
- **Performance**: Resource constraints, operation limits
- **Security**: Validations, unsafe operations, compliance rules
- **Dependencies**: Authorized libraries, versions, licenses
- **Architecture**: Pattern violations, boundaries, coupling
</compliance-checks>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_edict_compliance.md`:

```markdown
# Edict Compliance Report
Target: [checked]
Date: YYYY-MM-DD HH:MM

## Summary
✅ Compliant: N
❌ Violations: N
⚠️  Warnings: N

## ❌ VIOLATIONS
### Edict.Category.N
**Violated**: [constraint]
**Found**: [violation]
**Location**: file:line
**Fix**: [required change]

## ⚠️  WARNINGS
[Potential issues with recommendations]

## Actions Required
1. [Priority fixes]
2. [Next steps]
```
</output>

Report violations clearly. If compliant, note redemption opportunities.