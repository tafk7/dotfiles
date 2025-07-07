---
description: Summarize unstaged changes since last commit
---

# /git:diff

Analyze unstaged changes since last commit and provide summary of modifications.

## Task

<task>Summarize unstaged changes since last commit $ARGUMENTS</task>

<requirements>
1. Analyze unstaged changes for modifications
2. Group related changes by component or feature
3. Provide clear summary of what changed
</requirements>

<output>
Terminal output (change summary)
</output>

<conditional>
If --staged: Include staged changes
If no changes: Show "No unstaged changes"
</conditional>

<error-handling>
Not a git repository: Exit with clear message
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: Show unstaged changes
# - --staged: Include staged changes
# - file/path: Show changes for specific area

Understanding change is the first step toward intentional progress.