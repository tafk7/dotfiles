---
description: Create user-facing documentation explaining code/concepts
---

# Explain

Deep analysis of $ARGUMENTS to build understanding and generate explanatory report.

## Task

<task>Understand and explain $ARGUMENTS comprehensively</task>

<requirements>
1. Build complete understanding of how it works
2. Identify key patterns and design decisions
3. Create clear, navigable documentation
4. Focus on user comprehension
</requirements>

<phases>
1. **Analyze** - Understand structure and flow
2. **Synthesize** - Extract key insights
3. **Document** - Create clear explanation
</phases>

<output>
artifacts/analyses/YYMMDD_HHMM_explain_[target].md
</output>

<conditional>
If single file: Function-level detail
If large system: Focus on core concepts
If no code: Explain available documentation
</conditional>

<error-handling>
Target unclear: Ask for specific file or topic
Too broad: Suggest narrower scope
</error-handling>

Understanding is seeing the system as its creators intended.