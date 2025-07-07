---
description: Incremental improvement recommendations with checklist
---

# /refine

Analyze $ARGUMENTS and provide incremental improvement recommendations with implementation checklist.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Git status: !`git status --porcelain 2>/dev/null | wc -l || echo "0"` uncommitted changes
- Test command: !`grep -E "test|spec" package.json 2>/dev/null | grep -oE '"[^"]+"' | head -1 | cut -d'"' -f2 || echo "No tests found"`
- Coverage: !`find . -name "*.json" -path "*/coverage/*" 2>/dev/null | head -1 | xargs grep -o '"pct":[0-9.]*' 2>/dev/null | head -1 | cut -d: -f2 || echo "Unknown"`%
- Files: !`find ${ARGUMENTS:-.} -type f -name "*.js" -o -name "*.ts" -o -name "*.py" 2>/dev/null | wc -l || echo "0"`

## Task

<task>Analyze and recommend incremental improvements for $ARGUMENTS</task>

<requirements>
1. Identify 3-5 improvements balancing impact vs risk
2. Provide clear implementation steps for each
3. Create actionable checklist for developer
4. Include rollback strategies
5. Estimate effort and impact
</requirements>

<phases>
1. **Analyze** - Code quality assessment
2. **Identify** - Improvement opportunities
3. **Prioritize** - By impact/risk ratio
4. **Document** - Actionable checklist
</phases>

<output>
Create `artifacts/checklists/YYMMDD_HHMM_refine_checklist.md`:

```markdown
# Refinement Checklist: [Target]
Date: YYYY-MM-DD HH:MM | Scope: [X files, Y functions]

## Quick Wins (< 30min each)
- [ ] **[Improvement]**: [Specific change]
  - File: `path/to/file.ext:123`
  - Impact: [What this fixes/improves]
  - Test: [How to verify]

## High Impact/Low Risk (1-2h each)
- [ ] **[Improvement]**: [Specific change]
  - Current: [Problem code/pattern]
  - Proposed: [Better approach]
  - Steps:
    1. [First step]
    2. [Second step]
  - Validation: [Test command]
  - Rollback: [How to undo if needed]

## Medium Risk Improvements (2-4h each)
- [ ] **[Improvement]**: [Specific change]
  - Risk: [What could break]
  - Mitigation: [How to prevent]
  - Steps:
    1. [Detailed step]
    2. [Detailed step]
  - Rollback: [How to undo if needed]

## Summary
- Total effort: ~[X] hours
- Test coverage impact: [Current]% → [Expected]%
- Complexity reduction: [Metrics]
- Performance impact: [Expected gains]

## Next Steps
1. Review and prioritize items
2. Create feature branch
3. Implement incrementally
4. Run tests after each item
5. Update this checklist as you progress
```
</output>

<conditional>
If tests exist: Include test commands | If no tests: Recommend test creation first
If high complexity: Focus on simplification | If patterns: Focus on consistency
If performance issues: Include profiling steps | If security: Highlight vulnerabilities
Errors: Missing files(skip), Access denied(note permission issue)
</conditional>

<error-handling>
File not found: Skip and note in output
Parse errors: Document as high-priority fix
Large files: Analyze sample, note limitation
Binary files: Skip with explanation
</error-handling>

<rules>
- Recommendations only, no direct changes
- Each item must be independently actionable
- Include specific file locations and line numbers
- Provide effort estimates
- Always include rollback strategies
</rules>

# Arguments: $ARGUMENTS accepts:
# - No args: Current directory
# - path: Specific file/directory
# - --focus [complexity|performance|patterns]: Refinement focus
# - --depth [shallow|deep]: Analysis depth

Better code through thoughtful, incremental change.