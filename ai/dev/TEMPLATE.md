---
description: [Action-oriented description, max 10 words]
---

# COMMAND TEMPLATE
# This file defines the standard format for all slash commands.
# Copy this template when creating new commands and maintain consistency.

# [Command Name]

[Brief description incorporating $ARGUMENTS - one line explaining what this command does]

## Context
- [Primary metric]: !`echo "${ARGUMENTS:-.}"` 
- [Status check]: !`[command] 2>/dev/null && echo "Yes" || echo "No"`
- [Numeric count]: !`[command] 2>/dev/null | wc -l || echo "0"`
- [Complex query]: !`[command with ${ARGUMENTS:-default}] 2>/dev/null | [process] || echo "fallback"`

## Task

<task>[Verb] [object] for $ARGUMENTS</task>

<requirements>
1. [First requirement - specific and measurable]
2. [Second requirement - clear deliverable]
3. [Third requirement - concrete outcome]
4. [Additional requirements as needed]
</requirements>

<phases>
1. **[Phase]** - [Brief description] | 2. **[Phase]** - [Description]
3. **[Phase]** - [Description] | 4. **[Phase]** - [Final phase]
</phases>

<output>
Create `artifacts/[subdir]/YYMMDD_HHMM_[command]_[description].md`:

```markdown
# [Report Title]: [Target]
Date: YYYY-MM-DD HH:MM | [Key metric]: [Value]

## [Main Section]
[Content structure appropriate to command purpose]

## [Secondary Section]
[Supporting information]

## [Action/Summary Section]
[Next steps or key takeaways]
```
</output>

<conditional>
If [condition]: [Action] | If [related]: [Action] | If [related]: [Action]
If [different condition]: [Different action]
Errors: [Error type]([handling]), [Another error]([resolution])
</conditional>

<error-handling>
[Common error]: [Specific resolution]
[File/permission issue]: [Graceful fallback]
[Missing dependency]: [Clear message and alternative]
[Invalid input]: [Default behavior or prompt]
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: [Default behavior - typically current directory]
# - [pattern]: [What this pattern does]
# - [--flag]: [What this flag enables]
# - [value type]: [How different values are interpreted]

[Philosophy statement - memorable principle that captures the essence of this command]