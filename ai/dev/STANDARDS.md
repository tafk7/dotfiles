# Slash Command Standards

This document defines the standardized formats for slash commands based on analysis of existing patterns.

## Core Principle: Trust the AI

The AI is highly intelligent and knows how to code, gather context, and solve problems. Commands should:
- Specify goals and constraints, not implementation details
- Provide guidance and workflow structure, not step-by-step instructions
- Focus on what makes this command unique, not what the AI already knows

## Format Decisions

### 1. **Conditional Format**
Use `If X: Y` format with pipe separators for related conditions:
```
If deep: Full analysis | If quick: Top issues only
If CRITICAL: Skip checks, minimal fix only
Errors: Missing file(exit), Invalid input(prompt)
```

### 2. **Shell Commands**
Place `2>/dev/null` immediately after potentially failing commands:
```
- Good: !`grep pattern file 2>/dev/null | wc -l || echo "0"`
- Bad: !`grep pattern file | wc -l 2>/dev/null || echo "0"`
```

### 3. **Output Structure**
Keep output specifications minimal:
```markdown
<output>
artifacts/[type]/YYMMDD_HHMM_[command]_[description].md
</output>
```
Only include templates when consistent visual structure is critical.

### 4. **Philosophy Statements**
- Place as final line of command
- Use regular text (no italics)
- Create memorable, principle-based statement

### 5. **Phases**
- **<phases>**: High-level workflow overview (3-5 brief phases)
  - Use pipe separators (`|`) for parallel/related phases
  - Use numbered list for sequential phases that must complete in order
  - Keep phases conceptual, not prescriptive
  - Avoid detailed step-by-step instructions

### 6. **Error Handling**
Always include `<error-handling>` section with common failures:
```
<error-handling>
File not found: List alternatives
Permission denied: Check ownership
Invalid input: Use default value
</error-handling>
```

### 7. **Argument Documentation**
Document as comments after error-handling:
```
# Arguments: $ARGUMENTS accepts:
# - No args: Current directory
# - filename: Specific file to analyze
# - --flag: Enable special mode
```

## Consistency Checklist

- [ ] YAML front matter with concise description
- [ ] Title matches filename
- [ ] Brief description uses $ARGUMENTS
- [ ] Context section only if specific focus needed
- [ ] <task> tag clearly states the goal
- [ ] <requirements> focus on outcomes, not methods
- [ ] <phases> provide high-level workflow if complex
- [ ] <output> specifies artifact path
- [ ] <conditional> covers major variations
- [ ] <error-handling> addresses common failures simply
- [ ] Arguments documented concisely
- [ ] Philosophy statement captures essence

## File Naming

- Commands: `[verb].md` or `[noun].md`
- Outputs: `artifacts/[subdir]/YYMMDD_HHMM_[command]_[description].md`
- Issues: `artifacts/issues/TODO-YYMM-NNN_[description].md`

## Optional Sections

Commands may include optional sections when they add unique value:

### `<template>` Section
Use sparingly when consistent visual structure is critical for the AI's output:
- Analysis reports that need specific formatting
- Structured documentation that follows a precise pattern
- Outputs where visual consistency matters for readability

## Simplification Guidelines

1. **Remove Redundancy**: If the AI already knows how to do something, don't explain it
2. **Trust Intelligence**: Specify goals and constraints, let the AI determine implementation
3. **Merge Similar Commands**: Combine commands with overlapping purposes
4. **Minimal Context**: Only gather context that changes behavior
5. **Concise Requirements**: Focus on unique aspects of this command

The goal is clarity through simplicity, not exhaustive specification.