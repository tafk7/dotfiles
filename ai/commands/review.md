# Perfect Code Review{{#if file}} - {file}{{/if}}

Analyzing code against Perfect Code Framework principles...

## Review Checklist

### Prime Directives
- [ ] **Lex Prima**: Is this the highest quality solution possible?
- [ ] **Lex Secunda**: Are we maintaining unnecessary compatibility?
- [ ] **Lex Tertia**: Is this the simplest possible approach?

### Core Axioms
- [ ] **Deletion**: Can any code be removed?
- [ ] **Standards**: Are we using established patterns?
- [ ] **Clarity**: Will a junior developer understand this?
- [ ] **Courage**: Did we avoid compromise from fear?
- [ ] **Libraries**: Did we check for existing solutions?

### Project Canons
{{#if (exists "CLAUDE.md")}}
Checking against project-specific rules...
{{else}}
No project CLAUDE.md found - using global framework only.
{{/if}}

## Analysis Focus
1. **Complexity**: Cyclomatic complexity, nesting depth, line count
2. **Patterns**: Alignment with industry standards
3. **Dependencies**: Appropriate library usage
4. **Clarity**: Naming, structure, documentation needs
5. **Opportunities**: Potential improvements through refactoring

*Detailed findings will be provided based on code context.*
