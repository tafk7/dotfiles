---
description: [Action-oriented description, max 10 words]
---

# COMMAND TEMPLATE
# This file defines the standard format for all slash commands.
# Copy this template when creating new commands and maintain consistency.

# [Command Name]

[Brief description incorporating $ARGUMENTS - one line explaining what this command does]

## Context
# Optional: Include only when specific context focus/exclusion is needed
- [Key metric]: !`echo "${ARGUMENTS:-.}"` 
- [Status check]: !`[command] 2>/dev/null && echo "Yes" || echo "No"`
- [Count]: !`[command] 2>/dev/null | wc -l || echo "0"`

## Task

<task>[Verb] [object] for $ARGUMENTS</task>

<requirements>
1. [Primary goal or deliverable]
2. [Key constraint or quality standard]
3. [Important outcome if needed]
</requirements>

<phases>
# Choose format based on workflow:
# Option A - Parallel/grouped phases (can happen together):
1. **[Phase]** - [Brief description] | 2. **[Phase]** - [Description]
3. **[Phase]** - [Description] | 4. **[Phase]** - [Final phase]

# Option B - Sequential phases (must happen in order):
1. **[Phase]** - [Must complete before next]
2. **[Phase]** - [Depends on previous]
3. **[Phase]** - [Depends on previous]
4. **[Phase]** - [Final sequential step]
</phases>

<output>
artifacts/[type]/YYMMDD_HHMM_[command]_[description].md
</output>

<conditional>
If [condition]: [Action] | If [related]: [Action]
If [different condition]: [Different action]
</conditional>

<error-handling>
[Common error]: [Simple resolution]
[Invalid input]: [Default behavior]
</error-handling>

# OPTIONAL SECTIONS (use when beneficial):

# <template> - For commands that generate structured output users need to fill
# <template>
# ```format
# [Template content for specific structured output]
# ```
# </template>

# Arguments: $ARGUMENTS accepts:
# - No args: [Default behavior - typically current directory]
# - [pattern]: [What this pattern does]
# - [--flag]: [What this flag enables]

[Philosophy statement - memorable principle that captures the essence of this command]