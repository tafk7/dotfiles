---
name: canon
description: Manage project-specific canons in local CLAUDE.md
parameters:
  - name: action
    type: string
    required: true
    choices: [init, add, check, show]
  - name: value
    type: string
    required: false
---

# Canon Management: {action}

{{#if (eq action "init")}}
Creating project-local CLAUDE.md with canon template...

This will create a CLAUDE.md in your project root that extends the global Perfect Code Framework with project-specific canons.

```markdown
# Project: [PROJECT_NAME]

This project extends the Perfect Code Framework with specific canons.

## Project Canons

### Architecture
<!-- Example: Canon.Architecture.1: Use hexagonal architecture with ports and adapters -->

### Technology Stack
<!-- Example: Canon.Stack.1: Python 3.11+ with type hints required -->

### Libraries & Frameworks
<!-- Example: Canon.Libraries.1: FastAPI for web framework (not Flask, not Django) -->

### Patterns & Practices
<!-- Example: Canon.Patterns.1: Use Result[T, E] for all fallible operations -->

### Performance Requirements
<!-- Example: Canon.Performance.1: All API endpoints must respond in <200ms -->

### Breaking Change Policy
<!-- Example: Canon.Breaking.1: Internal APIs can break freely -->

### Legacy Constraints
<!-- Example: Canon.Legacy.1: Must support legacy XML API until Q3 2025 -->

### Testing Requirements
<!-- Example: Canon.Testing.1: 90% coverage minimum for business logic -->

### Documentation Standards
<!-- Example: Canon.Docs.1: All public functions need docstrings -->

---

## Framework Overrides

<!-- Specify any modifications to the Perfect Code Framework for this project -->
<!-- Example: Due to legacy constraints, Lex Secunda is suspended for database schema -->

## Mode Defaults

Default mode for this project: `perfect` <!-- or 'ship' or 'incremental' -->

---

*Last Updated: {{date}}*
*Canonical Authority: [TECH_LEAD_NAME]*
```

File created! Edit CLAUDE.md to add your project-specific canons.
{{/if}}

{{#if (eq action "add")}}
{{#if value}}
## Adding Canon

**New Rule**: `{value}`

### Next Steps
1. Determine appropriate section:
   - Architecture (design decisions)
   - Technology Stack (version requirements)
   - Libraries & Frameworks (tool choices)
   - Patterns & Practices (coding standards)
   - Performance (speed/resource limits)
   - Breaking Change Policy (compatibility rules)
   - Legacy Constraints (must-maintain items)
   - Testing (coverage requirements)
   - Documentation (comment standards)

2. Add to project CLAUDE.md with proper numbering
3. Ensure rule is specific and measurable

*Example format*: `Canon.Section.N: Specific, measurable rule`
{{else}}
**Error**: Please provide a rule to add.

Usage: `/canon add "Canon.Category.N: Your rule here"`

Examples:
- `/canon add "Canon.Architecture.1: Use hexagonal architecture"`
- `/canon add "Canon.Performance.1: API responses < 200ms"`
- `/canon add "Canon.Testing.1: Minimum 90% coverage"`
{{/if}}
{{/if}}

{{#if (eq action "check")}}
Checking {{#if value}}{value}{{else}}current file{{/if}} against project canons...

Will verify compliance with canons defined in:
- Global CLAUDE.md (Perfect Code Framework)
- Local CLAUDE.md (Project Canons)

Reporting:
- ✅ Compliant rules
- ❌ Violations with line numbers
- ⚠️ Warnings for near-violations
{{/if}}

{{#if (eq action "show")}}
**Active Configuration**:
- Global: Perfect Code Framework
- Local: {{#if (exists "CLAUDE.md")}}✓ Project canons loaded{{else}}Using global defaults{{/if}}
{{/if}}---
name: canon
description: Manage project-specific canons in local CLAUDE.md
parameters:
  - name: action
    type: string
    required: true
    choices: [init, add, check, show]
  - name: value
    type: string
    required: false
---

# Canon Management: {action}

{{#if (eq action "init")}}
Creating project-local CLAUDE.md with canon template...

This will create a CLAUDE.md in your project root that extends the global Perfect Code Framework with project-specific canons.

```markdown
# Project: [PROJECT_NAME]

This project extends the Perfect Code Framework with specific canons.

## Project Canons

### Architecture
<!-- Example: Canon.Architecture.1: Use hexagonal architecture with ports and adapters -->

### Technology Stack
<!-- Example: Canon.Stack.1: Python 3.11+ with type hints required -->

### Libraries & Frameworks
<!-- Example: Canon.Libraries.1: FastAPI for web framework (not Flask, not Django) -->

### Patterns & Practices
<!-- Example: Canon.Patterns.1: Use Result[T, E] for all fallible operations -->

### Performance Requirements
<!-- Example: Canon.Performance.1: All API endpoints must respond in <200ms -->

### Breaking Change Policy
<!-- Example: Canon.Breaking.1: Internal APIs can break freely -->

### Legacy Constraints
<!-- Example: Canon.Legacy.1: Must support legacy XML API until Q3 2025 -->

### Testing Requirements
<!-- Example: Canon.Testing.1: 90% coverage minimum for business logic -->

### Documentation Standards
<!-- Example: Canon.Docs.1: All public functions need docstrings -->

---

## Framework Overrides

<!-- Specify any modifications to the Perfect Code Framework for this project -->
<!-- Example: Due to legacy constraints, Lex Secunda is suspended for database schema -->

## Mode Defaults

Default mode for this project: `perfect` <!-- or 'ship' or 'incremental' -->

---

*Last Updated: {{date}}*
*Canonical Authority: [TECH_LEAD_NAME]*
```

File created! Edit CLAUDE.md to add your project-specific canons.
{{/if}}

{{#if (eq action "add")}}
{{#if value}}
## Adding Canon

**New Rule**: `{value}`

### Next Steps
1. Determine appropriate section:
   - Architecture (design decisions)
   - Technology Stack (version requirements)
   - Libraries & Frameworks (tool choices)
   - Patterns & Practices (coding standards)
   - Performance (speed/resource limits)
   - Breaking Change Policy (compatibility rules)
   - Legacy Constraints (must-maintain items)
   - Testing (coverage requirements)
   - Documentation (comment standards)

2. Add to project CLAUDE.md with proper numbering
3. Ensure rule is specific and measurable

*Example format*: `Canon.Section.N: Specific, measurable rule`
{{else}}
**Error**: Please provide a rule to add.

Usage: `/canon add "Canon.Category.N: Your rule here"`

Examples:
- `/canon add "Canon.Architecture.1: Use hexagonal architecture"`
- `/canon add "Canon.Performance.1: API responses < 200ms"`
- `/canon add "Canon.Testing.1: Minimum 90% coverage"`
{{/if}}
{{/if}}

{{#if (eq action "check")}}
Checking {{#if value}}{value}{{else}}current file{{/if}} against project canons...

Will verify compliance with canons defined in:
- Global CLAUDE.md (Perfect Code Framework)
- Local CLAUDE.md (Project Canons)

Reporting:
- ✅ Compliant rules
- ❌ Violations with line numbers
- ⚠️ Warnings for near-violations
{{/if}}

{{#if (eq action "show")}}
**Active Configuration**:
- Global: Perfect Code Framework
- Local: {{#if (exists "CLAUDE.md")}}✓ Project canons loaded{{else}}Using global defaults{{/if}}
{{/if}}
