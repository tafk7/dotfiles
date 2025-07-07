---
description: Summarize unstaged changes since last commit
---

# /git:diff

Analyze unstaged changes since last commit and provide summary of modifications.

## Context
- Repository: !`git rev-parse --show-toplevel 2>/dev/null | xargs basename || echo "Not a git repo"`
- Branch: !`git branch --show-current 2>/dev/null || echo "No branch"`
- Unstaged: !`git diff --name-only 2>/dev/null | wc -l || echo "0"` files
- Staged: !`git diff --cached --name-only 2>/dev/null | wc -l || echo "0"` files
- Changes: !`git diff --stat 2>/dev/null | tail -1 | grep -o '[0-9]* insertion' | cut -d' ' -f1 || echo "0"`+/!`git diff --stat 2>/dev/null | tail -1 | grep -o '[0-9]* deletion' | cut -d' ' -f1 || echo "0"`-

## Task

<task>Summarize unstaged changes since last commit $ARGUMENTS</task>

<requirements>
1. Analyze unstaged changes for modifications and intent
2. Group related changes by component or feature
3. Provide clear summary of what changed and why
4. Suggest actionable next steps for workflow
</requirements>

<output>
Direct output to user:

```bash
# Unstaged Changes
Files: [X] | Lines: +[Y] -[Z]

## Modified Files
- [file]: [change type] ([lines])
- [file]: [change type] ([lines])

## Summary
- [What changed and why]
- [What changed and why]

## Next Steps
[git add files / continue development]
```
</output>

<conditional>
If --staged flag: Include staged changes | If no changes: Show "No unstaged changes"
If large changeset: Group by component | If new files: Highlight additions
Errors: Not git repo(exit), No commits(show all as new)
</conditional>

<error-handling>
Not a git repository: Exit with "Not in a git repository"
No unstaged changes: Display "No unstaged changes"
Large diff: Group changes by directory/component
</error-handling>

<rules>
- Focus on unstaged changes by default
- Group related changes together
- Provide actionable next steps
- Direct output only, no artifacts
</rules>

# Arguments: $ARGUMENTS accepts:
# - No args: Show unstaged changes since last commit
# - --staged: Include staged changes in analysis
# - file/path: Show changes for specific file/directory

Understanding change is the first step toward intentional progress.