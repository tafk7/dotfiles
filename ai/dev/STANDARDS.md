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
- [ ] <phases> use consistent format
- [ ] <output> specifies exact file path
- [ ] <conditional> groups related conditions
- [ ] <error-handling> covers common cases
- [ ] Arguments documented in comments
- [ ] Philosophy statement as final line

## File Naming

- Commands: `[verb].md` or `[noun].md`
- Outputs: `artifacts/[subdir]/YYMMDD_HHMM_[command]_[description].md`
- Issues: `artifacts/issues/TODO-YYMM-NNN_[description].md`