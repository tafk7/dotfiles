---
description: Apply The Sublime standard comprehensively to analyze and improve code
--

# Apply The Sublime Standard

Analyze code, files, or directories against The Sublime principles for comprehensive improvement recommendations.

## Context
- Current directory: !`pwd`
- Git status: !`git status -s 2>/dev/null || echo "Not a git repository"`
- Project edicts: !`test -f CLAUDE.md && echo "Project edicts found" || echo "No project edicts"`
- Recent changes: !`git diff --stat HEAD~1 2>/dev/null || echo "No recent changes"`

## Your Task

Perform a comprehensive analysis of $ARGUMENTS (or current directory if not specified) following The Sublime principles:

### 1. **Prime Directive Analysis**

Evaluate code against the three Prime Directives:

**Lex Prima: Code Quality is Sacred**
- Identify all quality issues, no matter how small
- Check for code smells and anti-patterns
- Evaluate maintainability and readability

**Lex Secunda: Truth Over Comfort**
- Report all problems honestly, even if fixes are breaking
- Identify technical debt without sugar-coating
- Assess the real state vs. the ideal state

**Lex Tertia: Simplicity is Divine**
- Find unnecessary complexity
- Identify over-engineered solutions
- Locate areas where less code would be better

### 2. **Core Axiom Application**

Apply each axiom systematically:

**Axiom of Deletion**
- Identify dead code and redundancy
- Find unused dependencies and imports
- Locate duplicate functionality

**Axiom of Standards**
- Custom implementations of standard patterns
- Non-idiomatic code
- Deviation from language best practices

**Axiom of Clarity**
- Code requiring excessive comments
- Unclear naming
- Convoluted logic flow

**Axiom of Courage**
- Breaking changes that would improve the system
- Fear-driven design decisions
- Compatibility compromises

**Axiom of Libraries**
- NIH (Not Invented Here) syndrome instances
- Custom code that duplicates library functionality
- Opportunities for well-tested libraries

**Axiom of Honest Progress**
- Fake or inadequate tests
- Misleading documentation
- Vanity metrics or false progress indicators

### 3. **Cardinal Sin Detection**

Map violations to their violated axioms:
- **Compatibility Worship** → violates Axiom of Courage
- **Wheel Reinvention** → violates Axiom of Libraries
- **Complexity Theater** → violates Axiom of Deletion & Simplicity
- **Progress Fakery** → violates Axiom of Honest Progress
- **Perfectionism Paralysis** → violates The Sublime Paradox

### 4. **Generate Comprehensive Analysis**

Create artifact: `artifacts/analyses/YYMMDD_HHMM_sublime_analysis.md`

Structure:
```markdown
# Sublime Analysis - [Target]
Date: YYYY-MM-DD HH:MM

## Executive Summary
- Overall health score: X/10
- Critical issues: N
- Quick wins available: N
- Estimated effort to reach Sublime: X days

## Critical Issues (P0)
Issues requiring immediate attention...

## Important Improvements (P1)
Significant quality improvements...

## Nice-to-Have Enhancements (P2)
Optimizations for consideration...

## Library Replacement Opportunities
| Current Code | Suggested Library | Benefit |
|--------------|-------------------|---------|
| ... | ... | ... |

## Breaking Change Recommendations
With migration paths...

## Quick Wins
Immediate improvements (< 1 hour each)...

## The Path to Sublime
Step-by-step plan to achieve excellence...
```

### 5. **Project Edict Compliance**

If project CLAUDE.md exists:
- Verify recommendations against project edicts
- Note where edicts prevent ideal solutions
- Suggest redemption timeline for constraints

### 6. **Action Items**

Conclude with prioritized actions:
- Immediate (today)
- Short-term (this sprint)
- Long-term (technical roadmap)

Remember: The Sublime is achieved through relentless honesty and continuous improvement. Be thorough, be specific, be transformative.
