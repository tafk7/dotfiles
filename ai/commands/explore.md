---
description: Quick experimentation mode for exploring ideas without quality constraints
---

# Exploration Mode

Rapid experimentation sandbox for $ARGUMENTS. Quality suspended. Discovery prioritized.

## Context
- Experiment: !`date "+%Y%m%d_%H%M"`
- Mode: EXPLORATION

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

<output>
Educational sketches + documented learnings + clear next steps

The code is disposable. The knowledge is permanent.
</output>