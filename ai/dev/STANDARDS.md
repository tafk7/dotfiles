# Slash Command Standards

This document defines the standardized formats for slash commands based on analysis of existing patterns.

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
Use triple backticks with markdown language identifier:
```markdown
<output>
Create `artifacts/[subdir]/YYMMDD_HHMM_[type]_[desc].md`:

```markdown
# Title: [Target]
Date: YYYY-MM-DD HH:MM | Metric: Value

## Section
Content
```
</output>
```

### 4. **Philosophy Statements**
- Place as final line of command
- Use regular text (no italics)
- Create memorable, principle-based statement

### 5. **Phases vs Process**
- **<phases>**: High-level overview (4-6 brief phases)
  - Use pipe separators (`|`) for parallel/related phases that can happen together
  - Use numbered list format for sequential phases that must complete in order
  - Examples:
    - Parallel: `1. **Scan** - Find issues | 2. **Analyze** - Assess impact`
    - Sequential: `1. **Parse** - Extract data` → `2. **Generate** - Create output`
  - Choose format based on workflow logic, not template appearance
- **<process>**: Detailed step-by-step instructions
- Both can coexist if needed

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
- [ ] Context section with shell commands
- [ ] <task> tag includes $ARGUMENTS
- [ ] <requirements> are numbered and specific
- [ ] <phases> use appropriate format (pipe for parallel, list for sequential)
- [ ] <output> specifies exact file path
- [ ] <conditional> groups related conditions
- [ ] <error-handling> covers common cases
- [ ] Arguments documented in comments
- [ ] Philosophy statement as final line

## File Naming

- Commands: `[verb].md` or `[noun].md`
- Outputs: `artifacts/[subdir]/YYMMDD_HHMM_[command]_[description].md`
- Issues: `artifacts/issues/TODO-YYMM-NNN_[description].md`

## Optional Sections

Commands may include optional sections when they add clarity:

### `<template>` Section
Use for commands that generate structured output users need to fill in:
- TODO creation commands
- Log entry formats
- Issue templates

### `<rules>` Section  
Use for commands with important constraints that don't fit requirements:
- Maximum limits (e.g., "Maximum 5 files")
- Quality guidelines
- Behavioral constraints

### `<visualization>` Section
Use for commands that create diagrams or visual output:
- Mermaid diagram guidance
- Formatting best practices
- Accessibility requirements

## Acceptable Variations

While consistency is important, these variations are acceptable:

1. **Complex Commands**: May use additional sections if they significantly improve clarity
2. **Specialized Tools**: Can adapt format to match their unique workflow
3. **Phase Details**: Can include detailed sub-phases in output section when needed
4. **Conditional Grouping**: Can use multi-line format for complex conditions

The goal is clarity and functionality, not rigid conformity.