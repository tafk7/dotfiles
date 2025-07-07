---
description: Remove old artifacts while preserving issues and context
---

# Artifacts Cleanup

Clean up: $ARGUMENTS

## Task

<task>Clean up artifacts older than specified threshold</task>

<requirements>
1. Identify cleanup candidates (default: >14 days old)
2. Preserve issues/, reference/, current devlog, BLOCKED_ files
3. Warn about READY_ files and referenced items
4. Execute removal after confirmation
</requirements>

<phases>
1. **Analyze** - Find candidates and check references
2. **Review** - Present findings with warnings
3. **Execute** - Remove with confirmation
</phases>

<output>
Terminal output (cleanup summary with confirmation prompt)
</output>

<conditional>
If --dry-run: Preview only, no removal
</conditional>

<error-handling>
Missing artifacts directory: Exit gracefully
Invalid threshold: Default to 14 days
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: 14-day default
# - Number: Days threshold (e.g., "30")
# - --dry-run: Preview only

Clean artifacts, free mind. Every byte reclaimed fuels future creation.