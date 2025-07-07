---
description: Performance analysis and bottleneck identification
---

# /profile

Performance analysis of $ARGUMENTS to identify bottlenecks and optimization opportunities.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Git status: !`git status --porcelain 2>/dev/null | wc -l || echo "0"` uncommitted changes
- Language: !`find ${ARGUMENTS:-.} \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) 2>/dev/null | head -1 | sed 's/.*\.//' || echo "mixed"`
- Files: !`find ${ARGUMENTS:-.} \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) 2>/dev/null | wc -l || echo "0"`
- LOC: !`find ${ARGUMENTS:-.} \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.java" \) 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}' || echo "0"`
- Tools: !`which perf 2>/dev/null || echo "none"` | !`which node 2>/dev/null && echo "node" || echo "none"` | !`which python 2>/dev/null && echo "python" || echo "none"`

## Task

<task>Profile and analyze performance characteristics of $ARGUMENTS</task>

<requirements>
1. Identify computational bottlenecks and hot paths
2. Analyze algorithmic complexity and memory patterns
3. Recommend specific optimization strategies with impact estimates
4. Provide benchmarking methodology for validation
</requirements>

<phases>
1. **Scan** - Identify performance-critical code paths
2. **Measure** - Analyze complexity and resource usage
3. **Diagnose** - Find bottlenecks and inefficiencies
4. **Recommend** - Propose optimization strategies
</phases>

<output>
Create `artifacts/analyses/YYMMDD_HHMM_performance_analysis.md`:

```markdown
# Performance Profile: [Target]
Date: YYYY-MM-DD HH:MM | LOC: [X] | Language: [Y]

## Critical Hotspots
### 🔥 High Impact (>50% execution time)
- **[Function/Method]** - `file.ext:123`
  - Complexity: O([complexity])
  - Issue: [Specific problem]
  - Impact: [Performance cost]
  - Fix: [Optimization approach]

### ⚠️ Medium Impact (10-50% execution time)
- **[Function/Method]** - `file.ext:456`
  - Issue: [Problem pattern]
  - Fix: [Better approach]
  - Effort: [Implementation time]

## Complexity Analysis
- **Nested loops**: [Count] instances
- **Recursive calls**: [Count] functions, max depth [X]
- **Database queries**: [Count] in loops, [Count] N+1 patterns
- **File I/O**: [Count] operations, [Count] synchronous

## Memory Patterns
- **Large objects**: [Objects > 1MB]
- **Collection growth**: [Unbounded arrays/maps]
- **Leaks suspected**: [Functions creating persistent refs]
- **GC pressure**: [High allocation rate areas]

## Optimization Roadmap
### Quick Wins (< 2h each)
- [ ] [Specific optimization] → Expected: [X]% improvement
- [ ] [Specific optimization] → Expected: [X]% improvement

### Major Optimizations (1-2 days each)
- [ ] [Algorithm change] → Expected: [X]x speedup
- [ ] [Architecture change] → Expected: [X]% memory reduction

## Benchmarking Plan
```bash
# Baseline measurement
[command to measure current performance]

# After optimization
[command to verify improvement]

# Load testing
[command for stress testing]
```

## Tools
- **Profiler**: [Language-specific setup]
- **Benchmark**: [Measurement commands]
```
</output>

<conditional>
If Python: Use cProfile, memory_profiler | If Node.js: Use --prof, clinic.js
If Go: Use pprof | If Java: Use async-profiler | If database: Check query plans
If web app: Check network calls | If I/O heavy: Analyze file operations
If large codebase: Sample analysis, focus on entry points | If no profiler: Recommend installation
Errors: No profiler(recommend installation), Large codebase(sample analysis)
</conditional>

<error-handling>
Missing profiler tools: Recommend installation and basic setup
Large codebase: Focus on entry points and hot paths
No performance issues: Document baseline for future reference
Binary files: Skip with explanation
Permission issues: Note access requirements
</error-handling>

<rules>
- Focus on measurable performance impacts
- Provide specific file locations and line numbers
- Include complexity analysis (Big O notation)
- Recommend appropriate profiling tools
- Always include benchmarking methodology
</rules>

# Arguments: $ARGUMENTS accepts:
# - No args: Profile current directory
# - path: Specific file/directory to analyze
# - --deep: Include dependency analysis
# - --memory: Focus on memory usage patterns
# - --cpu: Focus on computational bottlenecks

Optimization without measurement is merely superstition - measure first, optimize with precision.