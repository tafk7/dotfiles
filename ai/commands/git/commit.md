---
description: Generate commit message from staged changes
---

# /git:commit

Analyze staged changes to generate descriptive commit message based solely on content.

## Task

<task>Generate commit message for staged changes $ARGUMENTS</task>

<requirements>
1. Analyze staged changes for what was actually modified
2. Describe only the content changes, not improvements or claims
3. Use conventional commit format (type: description)
4. Present as executable git command
</requirements>

<output>
Terminal output (executable git command)
</output>

<error-handling>
Not a git repository: Exit with clear message
No staged changes: Suggest git add
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - No args: Analyze all staged changes
# - --amend: Generate message for amending last commit

Clean commits tell the story of intentional change.