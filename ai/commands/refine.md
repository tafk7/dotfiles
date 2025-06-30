---
name: refine
description: Refine code toward perfection through strategic improvements
parameters:
  - name: scope
    type: string
    required: false
    choices: [analyze, propose, impact]
    default: analyze
---

# Refinement Analysis{{#if (eq scope "propose")}} - Proposal Mode{{/if}}{{#if (eq scope "impact")}} - Impact Assessment{{/if}}

{{#if (eq scope "analyze")}}
## Scanning for Improvement Opportunities

Analyzing codebase for areas where breaking changes would yield significant benefits...

### Analysis Categories

#### 1. API Design Flaws
- Inconsistent naming conventions
- Poor parameter ordering
- Missing type safety
- Confusing return types
- Leaked implementation details

#### 2. Technical Debt
- Legacy compatibility layers
- Deprecated feature support
- Workarounds for old bugs
- Accumulated cruft
- Outdated patterns

#### 3. Performance Bottlenecks
- Inefficient data structures
- Synchronous operations that should be async
- N+1 query patterns
- Unnecessary serialization
- Resource leaks

#### 4. Architectural Issues
- Tight coupling
- Circular dependencies
- Violated boundaries
- Mixed concerns
- Poor separation of layers

### Questions to Answer

1. **What would we build if starting fresh today?**
2. **What compatibility are we maintaining unnecessarily?**
3. **Which changes would remove the most code?**
4. **What would make the API delightful to use?**
5. **Which refactors are we avoiding due to compatibility?**

### Cost-Benefit Framework

For each potential breaking change:
- **Cost**: Migration effort, user impact, support burden
- **Benefit**: Code reduction, performance gain, maintainability
- **Risk**: Adoption friction, alternative solutions
- **Timeline**: Deprecation period, migration window
{{/if}}

{{#if (eq scope "propose")}}
## Breaking Change Proposal Template

### 1. Current State
```
Description: [What exists today]
Problems: [Why it needs to change]
Technical debt: [What it's costing us]
```

### 2. Proposed Change
```
New approach: [What we'll build]
Benefits: [Why it's worth breaking]
Code impact: [Lines added/removed]
```

### 3. Migration Strategy
```
Phase 1: Add deprecation warnings
Phase 2: Provide migration tooling
Phase 3: Support both approaches
Phase 4: Remove old implementation
```

### 4. Example Migration
```language
// Before
oldAPI.doThing(param1, param2, param3)

// After
newAPI.doThing({
  param1,
  param2,
  param3
})

// Migration tool
npx migrate-to-new-api
```

### 5. Success Criteria
- [ ] 80% of users migrated
- [ ] Performance improvement measured
- [ ] Code complexity reduced
- [ ] Documentation updated
- [ ] Support burden decreased
{{/if}}

{{#if (eq scope "impact")}}
## Breaking Change Impact Assessment

### User Impact Analysis
- **Affected users**: [Estimate percentage]
- **Migration difficulty**: [Easy/Medium/Hard]
- **Breaking severity**: [Minor/Major/Critical]
- **Alternative paths**: [Available workarounds]

### Codebase Impact
- **Files affected**: [Count]
- **Lines to change**: [Estimate]
- **Dependencies impacted**: [List]
- **Test updates needed**: [Count]

### Timeline Estimation
- **Development**: [Hours/Days]
- **Migration tools**: [Hours/Days]
- **Documentation**: [Hours/Days]
- **Support period**: [Weeks/Months]

### Risk Assessment
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| User revolt | Low/Med/High | Low/Med/High | [Strategy] |
| Migration failures | Low/Med/High | Low/Med/High | [Strategy] |
| Hidden dependencies | Low/Med/High | Low/Med/High | [Strategy] |

### Go/No-Go Checklist
- [ ] Benefits clearly outweigh costs
- [ ] Migration path is reasonable
- [ ] Timeline allows proper deprecation
- [ ] Team capacity exists for support
- [ ] Executive buy-in obtained
{{/if}}

## Breaking Change Opportunities Found

*The analysis will identify specific opportunities in your codebase here*

### High-Value Targets
1. [Area needing breaking change]
   - Current cost: [maintenance burden]
   - Potential gain: [improvement expected]
   - User impact: [who's affected]

### Quick Wins
- Breaking changes with minimal user impact but high code quality gains

### Long-Term Improvements
- Fundamental architectural changes worth planning for

---

*Remember: Great software evolves through careful refinement. The goal is perfection through iteration.*
