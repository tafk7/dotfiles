---
descrption: Check project edict compliance
---

# Check Edicts

Check if $ARGUMENTS (or current directory) violates any project edicts (constraints).

> **Note**: This checks constraints (what you CAN'T do). Use `/sublime` to find improvements (what you SHOULD do).

## Context
- Target: !`echo "${ARGUMENTS:-current directory}"`
- CLAUDE.md: !`test -f CLAUDE.md && echo "Found" || echo "Not found"`
- Active edicts: !`grep -c "^### Edict\." CLAUDE.md 2>/dev/null || echo "0"`
- Expired edicts: !`grep -B2 "Expires:" CLAUDE.md 2>/dev/null | grep -E "(202[0-9]|Never)" | awk -v today=$(date +%Y-%m-%d) '$2 < today {count++} END {print count+0}'`

## Your Task

**1. Prerequisites**

If no CLAUDE.md:
```
No project edicts found.
Run /init to create project configuration.
```

**2. Parse Edicts**

Extract each edict:
- Identifier (Edict.Category.N)
- Constraint description
- Expiration date/condition
- Context file reference

**3. Analyze Compliance**

Check target against each active edict:

**Compatibility**
- API contract violations
- Breaking changes to interfaces
- Data format modifications

**Performance**
- Operations exceeding constraints
- Resource-heavy patterns
- Unoptimized algorithms

**Security**
- Missing validations
- Unsafe operations
- Compliance violations

**Dependencies**
- Unauthorized libraries
- Version conflicts
- License violations

**Architecture**
- Pattern violations
- Boundary crossings
- Coupling issues

**4. Generate Report**

Create `artifacts/analyses/YYMMDD_HHMM_edict_compliance.md`:

```markdown
# Edict Compliance Report
Target: [what was checked]
Date: YYYY-MM-DD HH:MM

## Summary
✅ Compliant: N
❌ Violations: N
⚠️  Warnings: N
🕐 Expired: N

## ❌ VIOLATIONS

### Edict.Category.N
**Violated**: [specific constraint]
**Found**: [what code violates it]
**Location**: file:line
**Fix**: [required change]

## ⚠️  WARNINGS

### Edict.Category.N
**Risk**: [potential issue]
**Location**: file:line
**Recommend**: [preventive action]

## 🕐 EXPIRED EDICTS
[List with removal recommendations]

## 💡 REDEMPTION OPPORTUNITIES
Based on code quality improvements:
- [Edict that could be relaxed]
- [Constraint no longer needed]

## Actions Required
1. [Fix violations first]
2. [Address warnings]
3. [Review expired edicts]
```

**5. Exit Strategy**

If violations found:
- List violations clearly
- Suggest: "Fix violations or use /ship if urgent"
- Return error status

If compliant:
- Highlight redemption opportunities
- Note progress toward Sublime
- Suggest: "Run /sublime to find improvement opportunities"

**Output**: Compliance status + actionable report + redemption opportunities
