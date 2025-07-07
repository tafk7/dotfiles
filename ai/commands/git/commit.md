---
description: Generate commit message from staged changes
---

# /git:commit

Analyze staged changes and recent devlog entries to generate descriptive commit message.

## Context
- Repository: !`git rev-parse --show-toplevel 2>/dev/null | xargs basename || echo "Not a git repo"`
- Branch: !`git branch --show-current 2>/dev/null || echo "No branch"`
- Staged: !`git diff --cached --name-only 2>/dev/null | wc -l || echo "0"` files
- Changes: !`git diff --cached --stat 2>/dev/null | tail -1 | grep -o '[0-9]* insertion' | cut -d' ' -f1 || echo "0"`+/!`git diff --cached --stat 2>/dev/null | tail -1 | grep -o '[0-9]* deletion' | cut -d' ' -f1 || echo "0"`-
- Last commit: !`git log -1 --format="%h %s" 2>/dev/null || echo "No commits"`

## Task

<task>Generate commit message for staged changes $ARGUMENTS</task>

<requirements>
1. Analyze all staged changes for semantic meaning
2. Review devlog entries since last commit for context
3. Generate conventional commit format message
4. Present as executable git command for approval
</requirements>

<output>
Direct output to user:

```bash
# Staged Changes
Files: [X] | Lines: +[Y] -[Z]
- [file]: [change type]
- [file]: [change type]

# Proposed Commit
git commit -m "[type]: [description]

[optional body with why/context]"

# Execute this command if approved ^
```
</output>

<conditional>
If no staged changes: Suggest git add first | If large changeset: Focus on primary purpose
If conventional commits: Use feat/fix/docs format | If breaking changes: Include BREAKING CHANGE
Errors: Not git repo(exit), No staged changes(suggest git add)
</conditional>

<error-handling>
Not a git repository: Exit with "Not in a git repository"
No staged changes: Suggest "git add" to stage files first
Large diff: Focus on primary change, mention "and other improvements"
</error-handling>

<rules>
- Use conventional commit format (type: description)
- Keep first line under 72 characters
- Focus on user-facing changes over implementation
- Present as copy-pasteable git command
</rules>

# Arguments: $ARGUMENTS accepts:
# - No args: Analyze all staged changes
# - --amend: Generate message for amending last commit

Clean commits tell the story of intentional change.