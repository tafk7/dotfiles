---
description: Build deep understanding and mental model of repository or topic
---

# Build Context

Deep analysis of $ARGUMENTS to establish comprehensive understanding before implementation.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Repository: !`git rev-parse --is-inside-work-tree 2>/dev/null && echo "Yes" || echo "No"`
- Code files: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" \) 2>/dev/null | wc -l || echo "0"`
- Lines: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0"`
- Tests: !`find "${ARGUMENTS:-.}" -name "*test*" -o -name "*spec*" 2>/dev/null | wc -l || echo "0"`

## Task

<task>Build comprehensive mental model of $ARGUMENTS</task>

<requirements>
1. Map architecture and dependencies
2. Identify core patterns and abstractions
3. Trace critical paths and data flows
4. Document design decisions and trade-offs
5. Create navigable knowledge artifacts
</requirements>

<phases>
1. **Survey** - Structure, stack, boundaries | 2. **Analyze** - Logic, patterns, flows
3. **Connect** - Dependencies, integrations | 4. **Model** - Architecture, decisions
5. **Document** - Context map and guide
</phases>

<conditional>
Small: Single file, essential flows | Large: Domain-focused files | No code: Docs/structure only
Library: API surface, usage | Application: User flows, data | Component: Deep narrow dive
</conditional>

<output>
```
========================================
         CONTEXT ANALYSIS
========================================
Target: [analyzed path/topic]
Type: [Library|App|Service|Tool]
Complexity: [Simple|Moderate|Complex]

## Core Understanding
Purpose: [One line value proposition]
Architecture: [Pattern/style used]
Key abstraction: [Central concept that unlocks understanding]

## Mental Model
[2-3 lines explaining how to think about this system]
"Think of X as Y because..."

## Critical Paths
1. Main flow: entry.py → process() → output
2. Error path: detect() → handle() → recover()
3. Data flow: input → transform → persist

## Navigation Guide
To understand X: Start with file.py:42, then related.py
Entry points: main.py | Core: services/*.py | Tests: tests/*.py
Key files: [Most important 3-5 files with purpose]

## Architecture Insights
- Pattern: Why used (benefit vs trade-off)
- Decision: Rationale (what it enables)
- Constraint: Impact (workaround if any)

## Gotchas & Mysteries  
! Surprising: [Non-obvious behavior]
? Unknown: [Unexplained design choice]
* Careful: [Common mistake area]

## Quick Start Paths
- Add feature: Start at X, follow pattern Y
- Debug issue: Check A, trace through B
- Understand Z: Read file:line, then file:line
```
</output>

<error-handling>
Huge codebase: Sample core paths | No docs: Infer from structure
Complex deps: Simplified view | Access denied: Available info only
</error-handling>

*Context is the lens through which chaos becomes clarity.*