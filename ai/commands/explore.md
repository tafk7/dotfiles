---
description: Quick experimentation mode for exploring ideas without quality constraints
---

# Exploration Mode

Rapid experimentation sandbox for $ARGUMENTS. Quality suspended. Discovery prioritized.

## Task

<task>Explore $ARGUMENTS</task>

<requirements>
1. Suspend quality constraints - speed and learning over polish
2. Try multiple approaches, keep failed attempts as learning
3. Document discoveries and key insights
4. Flag promising results for proper implementation
</requirements>

<phases>
1. **Experiment** - Try multiple approaches
2. **Learn** - Document what works and what doesn't
3. **Decide** - Flag if worth proper implementation
</phases>

<output>
artifacts/sketches/YYMMDD_HHMM_explore_[topic].[ext]
</output>

<conditional>
If errors: Keep as learning examples
If promising: Create elevation issue for production path
</conditional>

<error-handling>
No clear topic: Ask for specific area to explore
Too broad: Focus on one concrete aspect
</error-handling>

The code is disposable. The knowledge is permanent.