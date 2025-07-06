---
description: Apply The Sublime standard to analyze and improve code
---

# Apply The Sublime Standard

Analyze code against The Sublime principles for comprehensive improvement recommendations.

## Context
- Target: $ARGUMENTS (or current directory if not specified)
- Git status: !`git status -s 2>/dev/null || echo "Not a git repository"`
- Project config: !`test -f CLAUDE.md && echo "Project CLAUDE.md found" || echo "No project config"`

## Task

<task>Sublime Analysis</task>

<requirements>
1. Analyze code quality against Prime Directives
2. Apply Core Axioms to identify improvements
3. Detect Cardinal Sins and their violations
4. Generate prioritized recommendations
</requirements>

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

Be thorough, specific, and transformative. Focus on actionable improvements over philosophical discussion.