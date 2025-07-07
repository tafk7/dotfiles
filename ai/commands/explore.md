---
description: Quick experimentation mode for exploring ideas without quality constraints
---

# Exploration Mode

Rapid experimentation sandbox for $ARGUMENTS. Quality suspended. Discovery prioritized.

## Context
- Experiment: !`date "+%Y%m%d_%H%M"`
- Mode: EXPLORATION
- Language: !`echo "$ARGUMENTS" | grep -oE "(python|js|typescript|go|rust)" | head -1 || echo "auto"`
- Existing sketches: !`ls artifacts/sketches/*explore* 2>/dev/null | wc -l || echo "0"`

## Task

<task>Explore $ARGUMENTS</task>

<requirements>
1. Suspend quality constraints - speed and learning over polish
2. Create sketch file in `artifacts/sketches/` with experiment tracking
3. Try multiple approaches, keep failed attempts as comments
4. Document discoveries in devlog with learnings
5. Create elevation issue if results show promise
</requirements>

<phases>
1. **Setup** - Create exploration workspace
2. **Experiment** - Try multiple approaches
3. **Document** - Capture learnings
4. **Evaluate** - Determine next steps
</phases>

<output>
Create sketch file: `artifacts/sketches/YYMMDD_HHMM_explore_[topic].[ext]`:

```[language]
# Exploration: [Topic/Question]
# Date: YYYY-MM-DD HH:MM
# Status: [Active|Failed|Promising|Abandoned]
# Question: [What are we trying to learn?]

# Attempt 1: [Approach]
[code]

# FAILED: [What went wrong]
# [commented out failed code]

# Attempt 2: [Different approach]
[working code]

# Discoveries:
# - [Learning 1]
# - [Learning 2]
# Next: [What to try next or production path]
```

Update devlog with exploration summary and learnings.
</output>

<conditional>
If language detected: Use appropriate extension, add boilerplate, include imports | If similar exists: Reference and build on it
If errors: Keep as "FAILED:" comments | If promising: Create elevation issue with production path
Exploration types: Algorithm(complexity, edge cases) | API(endpoints, auth) | Library(alternatives, benchmarks) | Pattern(implementations, tradeoffs)
</conditional>

<error-handling>
No language detected: Use .txt extension with clear comments
Sketch directory missing: Create artifacts/sketches/ automatically  
Import errors: Document and try alternative approaches
Runtime failures: Keep as learning examples with error messages
</error-handling>

The code is disposable. The knowledge is permanent.