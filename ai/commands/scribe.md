---
description: Deep analysis and focused documentation generation for repositories or topics
---

# Scribe

Analyze $ARGUMENTS deeply, then generate focused documentation (1-5 files) appropriate to what you discover.

## Context
Current directory: !`pwd`
Is git repository: !`git rev-parse --is-inside-work-tree 2>/dev/null && echo "Yes" || echo "No"`
Source files: !`find . -type f \( -name "*.md" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" \) 2>/dev/null | wc -l || echo "0"`
Existing docs: !`find . -name "README.md" -o -name "docs" -type d 2>/dev/null | wc -l || echo "0"`
Target: $ARGUMENTS

## Task
<task>Analyze $ARGUMENTS to understand its essence, then create 1-5 documentation files that capture what matters most. Use mermaid diagrams to visualize architecture, workflows, and relationships.</task>

## Phases

1. **Discovery** - Map structure and assess scope
2. **Analysis** - Deep dive into patterns and purpose
3. **Synthesis** - Identify key documentation needs
4. **Documentation** - Generate human-readable artifacts

## Process

### Phase 1: Discovery
- Map structure, boundaries, and entry points
- Catalog existing documentation
- Assess complexity and scale

### Phase 2: Analysis
- Trace critical paths and workflows
- Identify core patterns and relationships
- Extract design decisions and trade-offs

### Phase 3: Synthesis
- Build comprehensive mental model
- Determine essential vs optional content
- Select optimal documentation structure

### Phase 4: Documentation
- Generate 1-5 focused files
- Create mermaid diagrams for clarity
- Ensure practical, maintainable output

<output>
Create permanent documentation in `docs/` (or specified location):

### Documentation Patterns
**Simple**: Single README with overview, quickstart, concepts, and examples
**Complex**: README + ARCHITECTURE + GUIDE + API/CONTRIBUTING as needed
</output>

<visualization>
### Mermaid Best Practices (see ~/.claude/mermaid_reference.md)
- Choose diagram type by purpose: flowchart (process), sequence (interactions), state (lifecycle), class (structure), ER (data)
- Use descriptive labels and consistent direction
- Quote special characters in node names: `["Node with/slash"]`
- Use colors that contrast with black/white text
- Include accessibility titles and descriptions
</visualization>


<conditional>
If small codebase: Single README with essential diagram
If complex system: 3-5 files with focused diagrams
If existing docs: Update and add visual aids
If unclear scope: Start with exploration diagram
</conditional>

<error-handling>
- No source files: Document from README/structure only
- Access denied: Note limitations in output
- Huge godebase: Sample key areas, note scope limits
- Missing context: Request clarification or proceed with assumptions
</error-handling>

<rules>
- Maximum 5 documentation files
- Prioritize clarity over completeness
- Include diagrams where they clarify, not complicate
- Explain the "why" before the "how"
- Use analogies and concrete examples
- Write for future confused developers
</rules>

*The best documentation teaches visually what words alone cannot convey.*
