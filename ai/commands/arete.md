---
description: Apply The Arete standard to analyze and improve code
---

# Apply The Arete Standard

Analyze code against The Arete principles for comprehensive improvement recommendations.

## Task

<task>Arete analysis of $ARGUMENTS</task>

<requirements>
1. Analyze code quality against Prime Directives
2. Apply Core Axioms to identify improvements
3. Detect Cardinal Sins and their violations
4. Generate prioritized recommendations with migration paths
</requirements>

<phases>
1. **Analyze** - Apply Arete principles
2. **Prioritize** - Rank improvements by impact
3. **Plan** - Create actionable roadmap
</phases>

<output>
artifacts/analyses/YYMMDD_HHMM_arete_analysis.md
</output>

<conditional>
If --deep: Include comprehensive metrics and analysis
</conditional>

<error-handling>
Large codebase: Sample intelligently
Target unclear: Ask for specific area
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: Current directory
# - path: Specific file/directory
# - --deep: Comprehensive analysis

Every deletion brings clarity. Every simplification reveals truth. Arete!