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

<task>Sublime analysis of $ARGUMENTS</task>

<requirements>
1. Analyze code quality against Prime Directives
   - Code smells and anti-patterns
   - Maintainability and readability issues
2. Apply Core Axioms to identify improvements
   - Unnecessary complexity and over-engineering
   - Opportunities for deletion and simplification
3. Detect Cardinal Sins and their violations
   - Non-idiomatic code and custom implementations
   - Library replacement opportunities
4. Generate prioritized recommendations
   - Breaking changes with migration paths
   - Long-term vs short-term tradeoffs
</requirements>

<phases>
1. **Scan** - Inventory codebase structure
2. **Analyze** - Apply Sublime principles
3. **Prioritize** - Rank improvements by impact
4. **Plan** - Create actionable roadmap
</phases>

<conditional>
If deep: dependency graphs, complexity, performance | If quick: top 5 issues, 1hr fixes, skip migration
Focus areas: Security(OWASP,auth,data) | Performance(BigO,cache,DB) | Maintainability(clarity,docs,tests) | Architecture(coupling,cohesion,SOLID)
</conditional>


<output>
Create `artifacts/analyses/YYMMDD_HHMM_sublime_analysis.md`:

```markdown
# Sublime Analysis - [Target]
Date: YYYY-MM-DD HH:MM

## Executive Summary
Health score: X/10 | Critical: N | Quick wins: N

## Critical Issues (P0)
[Immediate attention required]

## Important Improvements (P1)  
[Significant quality improvements]

## Library Replacements
| Current | Suggested | Benefit |
|---------|-----------|---------|

## Quick Wins (<1hr each)
[Low-effort, high-impact changes]

## Path to Sublime
[Prioritized action plan]
```
</output>

<error-handling>
- Large codebase: Sample intelligently, focus on hot paths
- Missing tests: Note as critical issue
- Legacy code: Provide incremental migration path
- External dependencies: Check for better alternatives
</error-handling>

Every deletion brings clarity. Every simplification reveals truth. The Sublime awaits.