---
description: Quick experimentation mode for exploring ideas without quality constrains
---

# Exploration Mode

Rapid experimentation sandbox for $ARGUMENTS. Quality suspended. Discovery prioritized.

## Context
- Experiment timestamp: !`date "+%Y%m%d_%H%M"`
- Mode: EXPLORATION
- Quality gates: DISABLED

## Your Task

### Exploration Principles

**Permission to be Messy**
The goal is learning, not shipping. Failed experiments are victories.

**Anything Goes:**
- Global variables? Fine.
- Console.log debugging? Perfect.
- Hardcoded values? Go for it.
- Copy from Stack Overflow? Absolutely.
- Performance? Ignore it.
- Security? Not today.
- Error handling? Skip it.
- Best practices? Suspended.

Speed matters. Understanding matters. Polish doesn't.

### Explore: $ARGUMENTS

1. **Create Sketch File**
   Generate in `artifacts/sketches/YYMMDD_HHMM_explore_[description].[ext]`

   Add header comment:
   ```
   /*
    * EXPLORATION SKETCH
    * Question: [What we're trying to learn]
    * Date: YYYY-MM-DD HH:MM
    * Status: EXPERIMENTAL
    */
   ```

2. **Experiment Freely**
   - Try multiple approaches in the same file
   - Leave failed attempts commented out (they're learning!)
   - Use print statements liberally
   - Break all the rules if it helps you learn faster

3. **Document Discoveries**
   Update `artifacts/devlog_YYMM.md`:
   ```markdown
   ## YYYY-MM-DD HH:MM - EXPLORATION: [Topic]

   **Question**: What happens if...?
   **Sketch**: [sketch filename]

   **Discoveries**:
   - [Thing learned]
   - [Surprise found]
   - [What didn't work and why]

   **Next Steps**:
   - [ ] Worth pursuing to production?
   - [ ] Need more exploration?
   - [ ] Dead end - document why
   ```

4. **If Promising** → Create Elevation Plan
   If the exploration shows promise, create issue in `artifacts/issues/`:
   ```markdown
   # Elevate Exploration: [Description]

   Created from: [sketch filename]

   ## What We Learned
   - [Key insights from exploration]

   ## Path to Production
   1. [How to properly implement]
   2. [Architecture considerations]
   3. [Required cleanup]

   ## Estimated Effort
   - Exploration took: X hours
   - Production version: Y hours
   ```

### What Exploration Creates

**Valuable Artifacts:**
- Learning documentation
- Proof of concepts
- Failed experiment insights
- Decision evidence

**Not Suitable For:**
- Production use
- Code examples
- Performance benchmarks
- Copy-paste templates

The code is disposable. The knowledge is permanent.

### The Explorer's Mindset

> "In exploration mode, the only failure is not learning something new"

Questions worth exploring:
- What happens if we try...?
- Is it even possible to...?
- How does X really work?
- What's the simplest way to...?
- Can we break this?

**Output**: Educational sketches + documented learnings + clear next steps
