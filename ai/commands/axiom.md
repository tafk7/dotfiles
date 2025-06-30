---
name: axiom
description: Apply and reinforce specific axioms from the Perfect Code Framework
parameters:
  - name: principle
    type: string
    required: true
    choices: [deletion, standards, clarity, courage, libraries]
---

# Axiom Focus: {principle}

{{#if (eq principle "deletion")}}
## Axiom of Deletion: Less code is better code (when functionality is preserved)

You are now focused on code deletion and minimization.

### Immediate Actions
1. Identify dead code
2. Find redundant implementations
3. Remove speculative features
4. Eliminate compatibility layers
5. Delete commented-out code

### Questions to Ask
- What code can be removed while preserving functionality?
- Are there unused functions, classes, or modules?
- Is there duplicated logic that can be consolidated?
- Are we maintaining code for scenarios that no longer exist?

### Red Flags
- "Might need this later" comments
- Compatibility code for deprecated versions
- Abstract classes with single implementations
- Unused configuration options
- Debug code in production
{{/if}}

{{#if (eq principle "standards")}}
## Axiom of Standards: Industry patterns exist for good reasons - use them

You are now focused on using established patterns and conventions.

### Immediate Actions
1. Identify custom implementations of standard patterns
2. Find wheels being reinvented
3. Check for industry-standard alternatives
4. Align with language idioms

### Questions to Ask
- Is this a solved problem in the ecosystem?
- What would the standard library do?
- How do major frameworks handle this?
- What pattern would a senior developer expect here?

### Common Violations
- Custom date/time handling
- Hand-rolled JSON parsing
- Homemade encryption
- DIY dependency injection
- Non-standard project structure
{{/if}}

{{#if (eq principle "clarity")}}
## Axiom of Clarity: Code that requires explanation has already failed

You are now focused on code clarity and self-documentation.

### Immediate Actions
1. Eliminate need for comments through better naming
2. Simplify complex conditionals
3. Extract magic numbers to named constants
4. Break down large functions
5. Use type hints/annotations

### Questions to Ask
- Would a new developer understand this immediately?
- Can I remove this comment by improving the code?
- Is the intent obvious from reading?
- Are the variable names self-documenting?

### Code Smells
- Comments explaining what (not why)
- Single-letter variables (except loop indices)
- Nested ternary operators
- Functions with more than 3 parameters
- Boolean flags that change behavior
{{/if}}

{{#if (eq principle "courage")}}
## Axiom of Courage: Fear of breaking changes leads to broken systems

You are now authorized to make breaking changes for better design.

### Immediate Actions
1. List all backwards compatibility code
2. Identify APIs that need redesign
3. Find deprecated features still supported
4. Question all "legacy" labels

### Questions to Ask
- What would this look like if designed today?
- What technical debt are we carrying?
- Which breaking changes would simplify everything?
- What migrations would our users thank us for?

### Breaking Change Checklist
- [ ] Document what breaks and why
- [ ] Provide migration path
- [ ] Set deprecation timeline
- [ ] Create migration tools if needed
- [ ] Communicate benefits clearly
{{/if}}

{{#if (eq principle "libraries")}}
## Axiom of Libraries: Well-tested libraries > custom implementations

You are now focused on leveraging existing libraries over custom code.

### Immediate Actions
1. Audit all custom utility functions
2. Search for library alternatives
3. List NIH (Not Invented Here) violations
4. Check for standard library equivalents

### Questions to Ask
- Has someone already solved this better?
- What libraries do similar projects use?
- Is this core to our business logic?
- Would a library be more maintained?

### Library Selection Criteria
- Active maintenance (recent commits)
- Good documentation
- Reasonable size
- Compatible license
- Community adoption
- Performance characteristics
{{/if}}

*Remember: This axiom focus is temporary. Return to balanced Perfect Code principles after addressing immediate concerns.*
