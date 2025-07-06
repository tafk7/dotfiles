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

<permissions>
Everything is allowed:
- Global variables, console.log debugging, hardcoded values
- Copy from Stack Overflow, ignore performance/security
- Failed attempts are valuable - keep them commented
- Speed and learning over polish
</permissions>

<process>
1. **Create sketch file**: `artifacts/sketches/YYMMDD_HHMM_explore_[topic].[ext]`
   - Use detected language extension or .txt
   - Add boilerplate header with question/date/status
   - Reference similar explorations if they exist

2. **Experiment freely** - Try multiple approaches, break rules, learn fast

3. **Document discoveries** in devlog with sketch filename, key learnings, next steps

4. **If promising**, create elevation issue with production path
</process>

<phases>
1. **Setup** - Create exploration workspace
2. **Experiment** - Try multiple approaches  
3. **Document** - Capture learnings
4. **Evaluate** - Determine next steps
</phases>

<conditional>
If language detected: Use appropriate extension, add boilerplate, include imports
If similar exploration exists: Reference previous attempts, build on lessons
If syntax/import/logic errors: Keep as "FAILED:" comments, document attempts
If promising results: Create elevation issue with production path

Exploration types for sketch headers:
- Algorithm: complexity, edge cases | API: endpoints, auth, responses  
- Library: alternatives, benchmarks | Pattern: implementations, tradeoffs
</conditional>

The code is disposable. The knowledge is permanent.