---
description: Design component structure for new systems
---

# /architect

Design component structure and key architectural decisions for new system $ARGUMENTS.

## Task

<task>Design component architecture for new system $ARGUMENTS</task>

<requirements>
1. Define 3-5 core components with clear responsibilities
2. Specify data flow and component interfaces
3. Recommend key technology choices with rationale
4. Provide concrete starting points for implementation
</requirements>

<phases>
1. **Analyze** - Understand requirements and constraints
2. **Design** - Define components and interfaces
3. **Document** - Create architecture with diagrams (see ~/.claude/mermaid_reference.md)
</phases>

<output>
artifacts/designs/YYMMDD_HHMM_architecture_[system].md
</output>

<error-handling>
Vague requirements: Ask for specific use cases
Overly complex: Suggest MVP scope
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - system-name: Name of new system to design
# - feature-name: New feature requiring architectural design
# - No args: Design for current directory context

Good architecture enables change; great architecture makes change obvious.