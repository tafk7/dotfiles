---
description: Performance analysis and bottleneck identification
---

# /profile

Performance analysis of $ARGUMENTS to identify bottlenecks and optimization opportunities.

## Task

<task>Profile and analyze performance characteristics of $ARGUMENTS</task>

<requirements>
1. Identify computational bottlenecks and hot paths
2. Analyze algorithmic complexity and memory patterns
3. Recommend specific optimization strategies with impact estimates
4. Provide benchmarking methodology for validation
</requirements>

<phases>
1. **Scan** - Identify performance-critical code
2. **Measure** - Analyze complexity and resource usage
3. **Diagnose** - Find bottlenecks and inefficiencies
4. **Recommend** - Propose optimization strategies
</phases>

<output>
artifacts/analyses/YYMMDD_HHMM_performance_analysis.md
</output>

<error-handling>
No clear performance issues: Document baseline
Target unclear: Ask for specific area
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: Profile current directory
# - path: Specific file/directory to analyze
# - --memory: Focus on memory usage patterns
# - --cpu: Focus on computational bottlenecks

Optimization without measurement is merely superstition - measure first, optimize with precision.