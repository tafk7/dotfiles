---
description: Create user-facing documentation explaining code/concepts
---

# Explain

Deep analysis of $ARGUMENTS to build understanding and generate explanatory report.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Type: !`[[ -f "${ARGUMENTS:-.}" ]] && echo "File" || [[ -d "${ARGUMENTS:-.}" ]] && echo "Directory" || echo "Topic"`
- Language: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | sed -E 's/.*\.([^.]+)$/\1/' | sort | uniq -c | sort -rn | head -3 | tr '\n' ' ' || echo "Unknown"`
- Size: !`find "${ARGUMENTS:-.}" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0"` lines
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
Date: YYYY-MM-DD HH:MM | Type: [Library/App/Service]

## What This Is
[One paragraph explaining purpose and value]
**In a nutshell**: [One-line summary]

## How It Works
[Core mechanism explained simply]

```mermaid
[Architecture diagram]
```

## Key Components
1. **[Component]**: [Purpose] → file:line
2. **[Component]**: [Purpose] → file:line
3. **[Component]**: [Purpose] → file:line

## Navigation Guide
- Start here: file:line - [Entry point]
- Core logic: file:line - [Main work]
- Key paths: [flow1] → [flow2] → [flow3]

## Mental Model
Think of this as [metaphor]. The key insight is [central concept].

[Additional sections as needed based on target type:]
- Design decisions (for complex systems)
- Domain concepts (for business logic)
- External connections (for integrations)
- Gotchas (if any surprises found)
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