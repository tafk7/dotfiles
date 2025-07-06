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

<conditional>
If language detected:
- Use appropriate extension
- Add language-specific boilerplate
- Include relevant imports

If similar exploration exists:
- Reference previous attempts
- Build on learned lessons
- Note evolution of understanding
</conditional>

<process>
1. **Create sketch file**: `artifacts/sketches/YYMMDD_HHMM_explore_[topic].[ext]`
   ```
   /*
    * EXPLORATION SKETCH
    * Question: [What we're trying to learn]
    * Date: YYYY-MM-DD HH:MM
    * Status: EXPERIMENTAL
    */
   ```

2. **Experiment freely** - Try multiple approaches, break rules, learn fast

3. **Document discoveries** in `artifacts/devlog_YYMM.md`:
   ```markdown
   ## YYYY-MM-DD HH:MM - EXPLORATION: [Topic]
   
   **Question**: What happens if...?
   **Sketch**: [filename]
   
   **Discoveries**:
   - [Key learning]
   - [Surprise found]
   - [What failed and why]
   
   **Next**: [ ] Production worthy? [ ] More exploration? [ ] Dead end?
   ```

4. **If promising**, create `artifacts/issues/elevate_[topic].md`:
   ```markdown
   # Elevate: [Description]
   From: [sketch filename]
   
   ## Learned
   - [Key insights]
   
   ## Production Path
   - [Implementation steps]
   
   ## Effort: X hours explored → Y hours to ship
   ```
</process>

<phases>
1. **Setup** - Create exploration workspace
2. **Experiment** - Try multiple approaches
3. **Document** - Capture learnings
4. **Evaluate** - Determine next steps
</phases>

# Output follows process documentation format above

The code is disposable. The knowledge is permanent.

<error-handling>
- Syntax errors: Keep as comments with "FAILED:" prefix
- Import errors: Document what was attempted
- Logic errors: Explain expected vs actual
- Performance issues: Note bottlenecks found
</error-handling>

# Exploration types (integrate into sketch header):
# - Algorithm: complexity, edge cases
# - API: endpoints, auth, responses
# - Library: alternatives, benchmarks  
# - Pattern: implementations, tradeoffs