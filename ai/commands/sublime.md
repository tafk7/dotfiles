---
description: Apply The Sublime standard to analyze and improve code
---

# Apply The Sublime Standard

Analyze code against The Sublime principles for comprehensive improvement recommendations.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Files to analyze: !`find "${ARGUMENTS:-.}" -type f -name "*.js" -o -name "*.ts" -o -name "*.py" -o -name "*.go" 2>/dev/null | wc -l || echo "0"`
- Git status: !`git status -s 2>/dev/null | wc -l || echo "No git"`
- Project config: !`test -f CLAUDE.md && echo "Found" || echo "Not found"`
- Analysis depth: !`[[ "$ARGUMENTS" == *"--deep"* ]] && echo "DEEP" || echo "STANDARD"`

## Task

<task>Sublime Analysis</task>

<requirements>
1. Analyze code quality against Prime Directives
2. Apply Core Axioms to identify improvements
3. Detect Cardinal Sins and their violations
4. Generate prioritized recommendations
</requirements>

<phases>
1. **Scan** - Inventory codebase structure
2. **Analyze** - Apply Sublime principles
3. **Prioritize** - Rank improvements by impact
4. **Plan** - Create actionable roadmap
</phases>

<conditional>
If deep analysis requested:
- Include dependency graphs
- Measure cyclomatic complexity
- Profile performance bottlenecks

If quick review requested:
- Focus on top 5 issues
- Provide 1-hour fixes
- Skip migration planning
</conditional>

<analysis>
### Quality Assessment
- Code smells and anti-patterns
- Maintainability and readability issues
- Technical debt identification

### Simplicity Review  
- Unnecessary complexity
- Over-engineered solutions
- Opportunities for deletion

### Standards Compliance
- Non-idiomatic code
- Custom implementations of standard patterns
- Library replacement opportunities

### Breaking Changes
- Improvements requiring breaking changes
- Migration paths for each change
- Long-term vs short-term tradeoffs
</analysis>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_sublime_analysis.md`:

```markdown
# Sublime Analysis - [Target]
Date: YYYY-MM-DD HH:MM

## Executive Summary
- Health score: X/10
- Critical issues: N
- Quick wins: N

## Critical Issues (P0)
[Immediate attention required]

## Important Improvements (P1)
[Significant quality improvements]

## Library Replacements
| Current | Suggested | Benefit |
|---------|-----------|---------|
| ...     | ...       | ...     |

## Quick Wins (<1hr each)
[Low-effort, high-impact changes]

## Path to Sublime
[Prioritized action plan]
```
</output>

# Focus areas (use --focus flag):
# - Security: OWASP top 10, auth patterns, data handling
# - Performance: Big-O analysis, caching, DB queries
# - Maintainability: clarity, docs, test coverage
# - Architecture: coupling, cohesion, SOLID

<error-handling>
- Large codebase: Sample intelligently, focus on hot paths
- Missing tests: Note as critical issue
- Legacy code: Provide incremental migration path
- External dependencies: Check for better alternatives
</error-handling>

Every deletion brings clarity. Every simplification reveals truth. The Sublime awaits.