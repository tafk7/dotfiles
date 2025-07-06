---
description: Deep analysis to understand and explain code/systems in artifacts/analyses
---

# Explain

Deep analysis of $ARGUMENTS to build understanding and generate explanatory report.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Type: !`[[ -f "${ARGUMENTS:-.}" ]] && echo "File" || [[ -d "${ARGUMENTS:-.}" ]] && echo "Directory" || echo "Topic"`
- Language: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | sed -E 's/.*\.([^.]+)$/\1/' | sort | uniq -c | sort -rn | head -3 | tr '\n' ' ' || echo "Unknown"`
- Size: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0"` lines
- Tests: !`find "${ARGUMENTS:-.}" -name "*test*" -o -name "*spec*" 2>/dev/null | wc -l || echo "0"`

## Task

<task>Understand and explain $ARGUMENTS comprehensively</task>

<requirements>
1. Build complete mental model of how it works
2. Map architecture, flow, and relationships
3. Identify patterns and design decisions
4. Document understanding clearly
5. Create navigable knowledge map
</requirements>

<phases>
1. **Survey** - Structure, boundaries, components | 2. **Trace** - Flows, dependencies, interactions
3. **Understand** - Patterns, decisions, trade-offs | 4. **Explain** - Clear documentation
</phases>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_explain_[target].md`:

```markdown
# Understanding: [Target]
Date: YYYY-MM-DD HH:MM | Type: [Library/App/Service] | Complexity: [Simple/Moderate/Complex]

## What This Is
[One paragraph explaining purpose and value]
**In a nutshell**: [One-line summary]
**Think of it as**: [Helpful metaphor or analogy]

## How It Works
[Core mechanism explained simply]

### Architecture
[Mermaid diagram showing structure/flow]

### Key Components
1. **[Component]**: [What it does] (location: file:line)
2. **[Component]**: [Purpose and responsibility] (file:line)
3. **[Component]**: [Role in system] (file:line)

## Mental Model
To understand this system:
- [Key insight that unlocks understanding]
- [How components relate to each other]
- [Central pattern or philosophy]

## Navigation Guide
**Start here**: file:line - [Why this is the best entry point]
**Core logic**: file:line - [Where the main work happens]
**Configuration**: file:line - [How behavior is controlled]

### Important Paths
1. Main flow: entry.py → process() → output
2. Data flow: input → transform → persist
3. Error handling: detect() → handle() → recover()

## Design Decisions
**Pattern**: [What pattern] used because [rationale]
**Trade-off**: Chose [X] over [Y] to enable [benefit]
**Constraint**: Limited by [factor], worked around via [approach]

## How Things Connect
- External APIs: [How integrated]
- Database: [Interaction pattern]
- Dependencies: [Key libraries and why chosen]

## Domain Concepts
**[Term]**: In this codebase means [definition]
**[Concept]**: Implemented as [explanation]

## Surprising Discoveries
! [Non-obvious behavior or clever trick]
? [Design choice that's unclear]
* [Area requiring careful attention]

## Summary
This system [core purpose] by [main mechanism]. The key to understanding it is [central insight]. When navigating, remember [crucial concept].
```
</output>

<conditional>
Single file: Function-by-function explanation | Small system: Complete mapping
Large system: Core paths focus | Library: API surface + internals | Topic: Conceptual overview
</conditional>

<error-handling>
No code: Explain structure/docs | Access issues: Work with available | Complex: Simplified model
</error-handling>

Understanding is seeing the system as its creators intended.