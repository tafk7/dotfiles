---
description: Generate permanent project documentation in docs/
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

<requirements>
1. Maximum 5 documentation files per analysis
2. Prioritize clarity and visual understanding over completeness
3. Include mermaid diagrams where they clarify key concepts
4. Write for future confused developers
5. Explain the "why" before the "how"
</requirements>

<phases>
1. **Discovery** - Map structure and assess scope
2. **Analysis** - Deep dive into patterns and purpose
3. **Synthesis** - Identify key documentation needs
4. **Documentation** - Generate human-readable artifacts
</phases>

<output>
Create permanent documentation in `docs/` (or specified location):

**Simple Project**: Single README.md
```markdown
# [Project Name]
[One-line description]

## Overview
[What and why, with architecture diagram]

## Quick Start
[Minimal steps to get running]

## Core Concepts
[Key ideas with examples]

## API/Usage
[Main interfaces and patterns]
```

**Complex System**: Multiple focused files
- README.md - Overview and quick start
- ARCHITECTURE.md - System design with diagrams
- GUIDE.md - Detailed usage and workflows
- API.md - Reference documentation
- CONTRIBUTING.md - Development setup

### Visualization Guidelines
Use mermaid diagrams for:
- Architecture: flowchart TD for system overview
- Workflows: sequence diagrams for interactions
- State: stateDiagram-v2 for lifecycles
- Data: erDiagram for relationships
</output>

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

# Arguments: $ARGUMENTS accepts:
# - Directory path: Analyze entire codebase
# - Specific topic: Focus documentation on that area
# - "--update": Refresh existing documentation
# - Custom output path after "--output"

The best documentation teaches visually what words alone cannot convey.
