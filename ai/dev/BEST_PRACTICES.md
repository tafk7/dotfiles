# Best Practices for AI-Assisted Development

This guide covers best practices for using AI assistants with the Arete Framework slash command system.

## Quick Start

1. Commands live in `ai/commands/` directory
2. Use `/` to invoke commands (e.g., `/arete`, `/ship`, `/architect`)
3. Follow the artifacts workflow for experimental code
4. Trust the AI - avoid over-specifying

## CLAUDE.md Files

### Project CLAUDE.md
When working in a project with a CLAUDE.md file, the AI automatically reads it for context. Use it to store:

```markdown
## Essential Commands
- Build: `npm run build`
- Test: `npm test`
- Deploy: `./scripts/deploy.sh production`

## Code Style
- TypeScript with strict mode
- Functional components with hooks
- Comprehensive JSDoc comments

## Project Structure
- `/src/components` - React components
- `/src/services` - Business logic
- `/src/utils` - Shared utilities
```

### Global CLAUDE.md
Located at `~/.claude/CLAUDE.md` for system-wide preferences and the Arete philosophy.

## Using Slash Commands

### Command Location
Commands are stored in `ai/commands/` with a simple 3-tag format:

```markdown
---
description: Brief action description
---

# /commandname

<instructions>
Single sentence goal.
</instructions>

<approach>
How to approach the task.
</approach>

<context>
Target: $ARGUMENTS
</context>
```

### Using Commands

The framework provides 20 commands organized by purpose. See the full command reference in README.md for details.

### Command Arguments
Pass arguments after the command:
```
/architect user authentication system
/ship CRITICAL fix login bug
/arete src/api --deep
```

## Artifacts Workflow

The framework uses an artifacts-based workflow for clean separation of experimental and production code. See `workflow.md` for complete details on the artifacts system, including directory structure, naming conventions, and issue tracking.

## Writing Effective Prompts

### Trust the AI
The AI is intelligent. Avoid:
- Step-by-step instructions
- Explaining how to code
- Over-specifying implementation

Instead, focus on:
- Clear goals
- Important constraints
- Desired outcomes

### Good Prompt Examples

**Simple and Clear**
```
Fix the authentication timeout issue in the login component
```

**With Context**
```
Refactor the payment service to use the new stripe API v3, maintaining backward compatibility for existing subscriptions
```

**With Constraints**
```
Add user profile page following our existing component patterns, must work offline
```

### Avoid Over-Specification

❌ **Bad**: Detailed steps
```
First use grep to find all files, then open each one, check for the function, modify it carefully ensuring proper error handling...
```

✅ **Good**: Clear goal
```
Update all API endpoints to use the new authentication middleware
```

## Working with Git

### Commits
Use `/git:commit` for smart commits that:
- Analyze all changes
- Generate meaningful messages
- Follow conventional commit format
- Add co-author attribution

### Pull Requests
The AI can create PRs with:
- Comprehensive summaries
- Test plans
- Proper formatting

## Common Workflows

For detailed workflow examples including new feature development, quick fixes, code improvement, and experimentation patterns, see `workflow.md`.

## Key Principles

### The Arete Philosophy

See README.md for the complete philosophy and Prime Directives.

### Trust the AI
- Specify what, not how
- Focus on unique requirements
- Let AI handle implementation details

### Artifacts First
- Experiment in _artifacts/
- Promote when ready
- Keep production clean

## Tips for Success

1. **Clear Context** - Reference specific files and patterns
2. **Embrace Breaking Changes** - If they improve architecture
3. **Delete Liberally** - Less code is better code
4. **Real Testing** - No fake tests or wishful documentation
5. **Ship Pragmatically** - Perfect code that ships beats perfect code that doesn't

## Troubleshooting

**Command Not Found**
- Check command exists in `ai/commands/`
- Verify correct syntax: `/commandname arguments`

**Unexpected Behavior**
- Review command definition
- Check CLAUDE.md for project edicts
- Ensure arguments are passed correctly

**Quality vs Speed**
- Use `/ship` for deadlines
- Use `/arete` for quality focus
- Use `/refine` for balance

Remember: The framework is a tool to enable better development, not a rigid constraint. When in doubt, pursue Arete - code in its highest form.

Arete.