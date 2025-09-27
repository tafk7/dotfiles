# Slash Command Standards

This document defines the standardized format for slash commands in the Arete Framework.

## Core Principle: Trust the AI

Commands should specify goals and constraints, not implementation details. The AI knows how to code, gather context, and solve problems.

## Command Format

Every command follows this exact structure:

```markdown
---
description: [Concise action-oriented description (3-7 words)]
---

# /[commandname]

<instructions>
[Single sentence clearly stating what this command accomplishes.]
</instructions>

<approach>
[How to approach the task. Can be simple or use phases for complex workflows.]
</approach>

<context>
Target: $ARGUMENTS
[Additional context only if needed]
</context>
```

## Format Components

### 1. YAML Frontmatter
- **Required**: Always include `description` field
- **Style**: Active verbs, 3-7 words maximum
- **Examples**: "Design component structure and architecture", "Analyze code against Arete principles"

### 2. Command Header
- Format: `# /[commandname]`
- Single word preferred (architect, arete, ship)
- Compound for subcommands: `/git:commit`, `/_artifacts/status`

### 3. Instructions Tag
- **Purpose**: Single sentence goal statement
- **Style**: Clear, actionable, ends with period
- **Focus**: What to accomplish, not how

### 4. Approach Tag
- **Simple commands**: Single paragraph approach
- **Complex commands**: Phase-based structure
  ```
  Phase 1 - [Action]: [Description]
  Phase 2 - [Action]: [Description]
  Phase 3 - [Action]: [Description]
  Priority: [What matters most]
  Output: [Where results go]
  ```
- **Alternative**: Some commands use numbered lists for sequential steps

### 5. Context Tag
- **Always include**: `Target: $ARGUMENTS`
- **Optional additions**: Only when behavior changes based on context
- **Keep minimal**: Trust the AI to gather needed context

## Common Patterns

### Output Specifications
```
Output: Create [type] in _artifacts/[subdir]/
```

### Priority Statements
- "High-impact simplifications and deletions first"
- "Speed and learning over code quality"
- "Working code now, quality improvements later"

### Phase Names
- Phase 1: Analyze, Survey, Scan, Parse, Discovery
- Phase 2: Design, Check, Measure, Execute
- Phase 3: Document, Report, Synthesize, Diagnose

## File Organization

### Directory Structure
```
ai/commands/
├── architect.md         # Design commands
├── arete.md            # Quality analysis  
├── ship.md             # Fast delivery
├── hone.md             # Dead code removal
├── [...more commands]
├── _artifacts/          # Artifact management (5 commands)
│   ├── status.md
│   ├── todo.md
│   └── [...more]
└── git/               # Git operations
    ├── commit.md
    └── diff.md
```

### Naming Conventions
- Commands: `[verb].md` or `[noun].md`
- Issues: `TODO-YYMM-NNN_[description].md`

## Creating New Commands

1. **Check existing commands first** - Reuse before creating
2. **Start from TEMPLATE.md** - Maintain consistency
3. **Focus on uniqueness** - What makes this command special?
4. **Test locally** - Ensure it works as intended
5. **Keep it simple** - Less specification, more trust

## Examples

### Good: Simple and Clear
```markdown
---
description: Ship working code with fastest path
---

# /ship

<instructions>
Deliver working solution prioritizing speed over perfection.
</instructions>

<approach>
Get it working with minimal changes. Log technical debt as TODO issues. Use existing patterns, skip non-critical features, focus on core functionality.
Priority: Working code now, quality improvements later.
Output: Create TODO-YYMM-NNN issues for cleanup.
</approach>

<context>
Target: $ARGUMENTS
</context>
```

### Bad: Over-Specified
```markdown
# /ship

<instructions>
This command helps you ship code quickly by following these steps...
</instructions>

<approach>
First, analyze the codebase using grep and find commands.
Then, implement the solution using proper error handling.
Make sure to validate input and handle edge cases.
Run tests with pytest or jest depending on the language.
Finally, create documentation...
</approach>

<error-handling>
If file not found: Create it
If permission denied: Use sudo
If syntax error: Fix it
</error-handling>
```

## Philosophy

Commands should enable, not constrain. They provide rails for common workflows while trusting the AI's intelligence to handle details. When in doubt, specify less and trust more.

Arete.