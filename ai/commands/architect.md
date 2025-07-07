---
description: Design component structure for new systems
---

# /architect

Design component structure and key architectural decisions for new system $ARGUMENTS.

## Context
- Target: !`echo "${ARGUMENTS:-.}"`
- Git status: !`git status --porcelain 2>/dev/null | wc -l || echo "0"` uncommitted changes
- Existing services: !`find . -name "package.json" -o -name "go.mod" -o -name "requirements.txt" -o -name "pom.xml" 2>/dev/null | wc -l || echo "0"`
- Current architecture: !`find . -name "docker-compose.yml" -o -name "Dockerfile" -o -name "*.service" 2>/dev/null | wc -l || echo "0"` containers/services
- Documentation: !`find . -name "README.md" -o -name "ARCHITECTURE.md" 2>/dev/null | wc -l || echo "0"` files

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
2. **Design** - Define components and responsibilities
3. **Connect** - Specify interfaces and data flow
4. **Recommend** - Select technologies and patterns
</phases>

<output>
Create `artifacts/designs/YYMMDD_HHMM_architecture_[system].md`:

```markdown
# Architecture Design: [System Name]
Date: YYYY-MM-DD HH:MM | Components: [X] | Complexity: [Low/Medium/High]

## System Overview
**Purpose**: [What this system does]
**Scale**: [Expected users/requests/data volume]
**Integration**: [How it connects to existing systems]

## Core Components
### [Component A] - [Primary Responsibility]
- **Role**: [What it handles]
- **Interface**: [Input/output data]
- **Technology**: [Recommended stack]

### [Component B] - [Primary Responsibility]
- **Role**: [What it handles]
- **Interface**: [Input/output data]
- **Technology**: [Recommended stack]

## Data Flow
[Mermaid diagram showing component relationships]

## Technology Stack
- **API Layer**: [Framework/tool with brief reason]
- **Data Storage**: [Database type with brief reason]
- **Communication**: [HTTP/gRPC/Events with brief reason]
- **Deployment**: [Container/serverless with brief reason]

## Implementation Order
1. **[Component A]** - Start here (foundation/core logic)
2. **[Component B]** - Add next (extends core functionality)
3. **[Component C]** - Final piece (integration/optimization)

## Key Decisions
- **[Decision 1]**: [Choice made and why]
- **[Decision 2]**: [Choice made and why]
- **[Decision 3]**: [Choice made and why]

## Next Steps
- [ ] Create project structure for [Component A]
- [ ] Set up [Database/API] scaffolding
- [ ] Implement [Core functionality] MVP
```
</output>

<conditional>
If microservice: Focus on service boundaries | If web app: Focus on layers
If data-heavy: Emphasize storage decisions | If real-time: Emphasize messaging
If existing system: Show integration points | If greenfield: Show full stack
Errors: Vague requirements(ask clarifying questions), Complex domain(simplify scope)
</conditional>

<error-handling>
Vague requirements: Ask for specific use cases and constraints
Overly complex scope: Suggest starting with core MVP components
No clear domain: Request problem statement and success criteria
Technology conflicts: Recommend based on team expertise
</error-handling>

<rules>
- Maximum 5 components in initial design
- Each component has single clear responsibility
- Technology choices must have brief rationale
- Include concrete next steps for implementation
- Focus on MVP architecture, not full-scale system
</rules>

<visualization>
Include mermaid diagram showing component relationships and data flow. See ~/.claude/mermaid_reference.md for best practices.
</visualization>

# Arguments: $ARGUMENTS accepts:
# - system-name: Name of new system to design
# - feature-name: New feature requiring architectural design
# - service-name: New microservice or component
# - No args: Design architecture for current directory context

Good architecture enables change; great architecture makes change obvious.