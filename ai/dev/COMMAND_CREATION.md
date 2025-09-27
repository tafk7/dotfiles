# Creating New Slash Commands

This guide walks through creating new commands for the Arete Framework.

## Before Creating a New Command

### 1. Check Existing Commands
Review `ai/commands/` to ensure your need isn't already met:
- Can an existing command handle this use case?
- Could you add an argument to an existing command?
- Is this truly a distinct workflow?

### 2. Identify the Purpose
Every command should have a clear position on the quality spectrum:
- **Quality Focus**: Like `/arete` for deep analysis
- **Balanced**: Like `/refine` for pragmatic improvements
- **Speed Focus**: Like `/ship` for urgent delivery
- **Experimental**: Like `/explore` for trying ideas

## Step-by-Step Guide

### Step 1: Copy the Template

```bash
cp ai/dev/TEMPLATE.md ai/commands/yourcommand.md
```

### Step 2: Define the Frontmatter

```yaml
---
description: [Active verb phrase, 3-7 words]
---
```

Examples:
- "Analyze code against Arete principles"
- "Ship working code with fastest path"
- "Build deep understanding of codebase"

### Step 3: Set the Command Name

```markdown
# /yourcommand
```

Guidelines:
- Single word preferred: `/architect`, `/ship`, `/hone`
- Compound for subcommands: `/git:commit`, `/_artifacts/status`
- Use verbs for actions: `/implement`, `/analyze`, `/create`
- Use nouns for tools: `/profile`, `/context`, `/edict`

### Step 4: Write Clear Instructions

```markdown
<instructions>
[Single sentence stating what the command accomplishes.]
</instructions>
```

Examples:
- "Design component structure and key architectural decisions for a new system."
- "Deliver working solution prioritizing speed over perfection."
- "Analyze code to build comprehensive mental model before implementation."

### Step 5: Define the Approach

For simple commands:
```markdown
<approach>
[Single paragraph describing how to approach the task. Include output location if applicable.]
</approach>
```

For complex commands with phases:
```markdown
<approach>
Phase 1 - Analyze: [Brief description]
Phase 2 - Design: [Brief description]
Phase 3 - Document: [Brief description]
Priority: [What matters most]
Output: Create [type] in _artifacts/[subdir]/YYMMDD_HHMM_[description].md
</approach>
```

### Step 6: Add Context

```markdown
<context>
Target: $ARGUMENTS
[Additional context only if behavior changes based on it]
</context>
```

Most commands only need `Target: $ARGUMENTS`. Add more only when necessary.

## Complete Example

Here's a complete example of a new command:

```markdown
---
description: Analyze security vulnerabilities and risks
---

# /security

<instructions>
Perform security analysis to identify vulnerabilities and recommend fixes.
</instructions>

<approach>
Phase 1 - Scan: Identify potential security issues in code and dependencies
Phase 2 - Analyze: Assess severity and exploitability of findings
Phase 3 - Report: Document vulnerabilities with remediation steps
Priority: Critical vulnerabilities that could lead to data breaches
Output: Create security report in _artifacts/analyses/YYMMDD_HHMM_security_analysis.md
</approach>

<context>
Target: $ARGUMENTS
</context>
```

## Testing Your Command

### 1. Local Testing
```bash
# Test with no arguments
/yourcommand

# Test with arguments
/yourcommand specific target

# Test edge cases
/yourcommand --flag value
```

### 2. Verify Output
- Check output location matches specification
- Ensure temporal naming is correct
- Verify artifact creation works

### 3. Integration Testing
- Test alongside related commands
- Ensure it fits the workflow
- Check for conflicts or overlaps

## Common Patterns

### Analysis Commands
```markdown
<approach>
Phase 1 - Scan: [What to examine]
Phase 2 - Analyze: [How to evaluate]
Phase 3 - Report: [What to produce]
Priority: [Focus area]
Output: Create analysis in _artifacts/analyses/
</approach>
```

### Implementation Commands
```markdown
<approach>
[Direct approach to building]. Create any needed artifacts.
Priority: [Speed vs quality tradeoff]
</approach>
```

### Utility Commands
```markdown
<approach>
[Simple action description]. 
Output: [Result location or action taken]
</approach>
```

## Naming Conventions

### Command Names
- Verbs: `/analyze`, `/create`, `/build`, `/ship`
- Nouns: `/profile`, `/context`, `/architect`
- Compounds: `/git:commit`, `/_artifacts/todo`

### Output Files
Use descriptive names that indicate the file's purpose:
```
_artifacts/[subdir]/[descriptive_filename].md
```

### Issue Tracking
For commands that create TODOs:
```
_artifacts/issues/TODO-YYMM-NNN_[description].md
```

## Do's and Don'ts

### Do's
✅ Keep instructions to one clear sentence
✅ Trust the AI to know how to code
✅ Focus on what makes this command unique
✅ Use consistent output patterns
✅ Test thoroughly before committing

### Don'ts
❌ Don't over-specify implementation details
❌ Don't duplicate existing functionality
❌ Don't include error handling (AI knows how)
❌ Don't make commands too specific

## Integration Checklist

Before finalizing your command:

- [ ] Command has clear, unique purpose
- [ ] Follows 3-tag format exactly
- [ ] Description is concise (3-7 words)
- [ ] Instructions are single sentence
- [ ] Output location specified if applicable
- [ ] Tested with various inputs
- [ ] No overlap with existing commands
- [ ] Fits within quality spectrum
- [ ] Documentation updated if needed

## Maintenance

### Evolving Commands
Commands can evolve, but maintain backward compatibility:
- Add new capabilities via arguments
- Don't change core behavior
- Document changes in approach section

### Deprecation
If a command becomes obsolete:
1. Add deprecation notice to description
2. Point to replacement command
3. Remove after grace period

### Quality Bar
Every command should:
- Serve a clear purpose
- Enable efficient workflows
- Follow framework philosophy
- Maintain format consistency

## Examples to Study

Study these well-designed commands:
- `/architect` - Clear phases, specific output
- `/ship` - Simple approach, philosophy alignment
- `/_artifacts/status` - Utility with options
- `/git:commit` - Integration with external tools

Remember: Less is more. Trust the AI. Focus on enabling workflows, not constraining them.

Arete.