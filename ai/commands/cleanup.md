---
description: Analyze code for dead weight, redundancy, and artifacts to polish for release
---

# Cleanup Analysis

Post-implementation analysis of $ARGUMENTS to identify and remove technical debris.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Size: !`du -sh "${ARGUMENTS:-.}" 2>/dev/null | cut -f1 || echo "0"`
- Tech debt: !`rg -c "TODO|FIXME|HACK|XXX" "${ARGUMENTS:-.}" 2>/dev/null | wc -l || echo "0"`
- Temp files: !`find "${ARGUMENTS:-.}" -name "*.tmp" -o -name "*.bak" -o -name "*.orig" -o -name "*~" 2>/dev/null | wc -l || echo "0"`

## Task

<task>Analyze $ARGUMENTS for cleanup opportunities</task>

<requirements>
1. Identify dead code and unused exports
2. Find duplicate implementations
3. Detect temporary/development artifacts
4. Generate prioritized cleanup plan
</requirements>

<phases>
1. **Scan** - Find cleanup targets | 2. **Risk** - Assess safety
3. **Report** - Actionable plan
</phases>

<conditional>
Production: Conservative | Feature branch: Aggressive
Tests exist: Bold cleanup | No tests: Flag all deletions
Language: JS/TS(imports) | Python(__all__) | Go(unused) | All(temp files)
</conditional>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_cleanup_analysis.md`:

```markdown
# Cleanup Analysis - [Target]
Date: YYYY-MM-DD HH:MM

## Summary
Dead code: N | Duplicates: N | Artifacts: N | Size: X MB → Y MB

## 🟢 Safe to Remove
- [ ] *.tmp, *.bak files (N files, X KB)
- [ ] console.log statements (N instances)
- [ ] Commented imports (N files)

## 🟡 Review First
- [ ] UnusedFunction() - file.js:42 - No refs found
- [ ] processData() ≈ transformData() - Merge?

## 🔴 Tech Debt
- TODO: Error handling - file.js:25
- Commented block - file.js:200-300

## Quick Commands
find . \( -name "*.tmp" -o -name "*.bak" -o -name "*.orig" -o -name "*~" \) -delete
rg -l "console\.log|debugger" | xargs -I {} sed -i.bak '/console\.log\|debugger/d' {}
git clean -ndx  # Preview untracked files (-fdx to delete)

## Verify After
- [ ] Tests pass
- [ ] Build succeeds
```
</output>

<error-handling>
Large codebase: Sample key directories | No tests: Mark high-risk
External deps: Check usage first | Binary files: Skip
</error-handling>

Polish reveals quality - remove the unnecessary to illuminate the essential.