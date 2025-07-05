---
descrption: Create issue file with full context
---

# Create TODO

Generate issue for: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Next ID: !`ls artifacts/issues/TODO-*.md 2>/dev/null | wc -l | xargs -I {} expr {} + 1 || echo "1"`
- Year: !`date "+%Y"`

## Your Task

Create `artifacts/issues/TODO-YYYY-NNN_description.md`:
(YYYY=year, NNN=zero-padded ID, description=snake_case summary)

```markdown
# $ARGUMENTS

**Created**: YYYY-MM-DD HH:MM
**Status**: Open
**Priority**: [P0: Blocking | P1: Important---
description: Create comprehensive issue file with full context
---

# Create TODO

Generate issue for: $ARGUMENTS

## Context
- Time: !`date "+%Y-%m-%d %H:%M"`
- Next ID: !`ls artifacts/issues/TODO-*.md 2>/dev/null | wc -l | xargs -I {} expr {} + 1 || echo "1"`
- Location: !`pwd`

## Your Task

Create `artifacts/issues/TODO-YYYY-NNN_description.md`:

```markdown
# $ARGUMENTS

**Created**: YYYY-MM-DD HH:MM
**Status**: Open
**Priority**: [P0: Blocking | P1: Important | P2: Enhancement]
**Effort**: [Small: <2hr | Medium: 2-8hr | Large: >1 day]

## Context
[Why this issue exists and how we got here]
[Link to devlog entry or PR where discovered]

## Current State
[What exists now - be specific]
[Include file paths and code snippets]
[What's broken or missing]

## Desired State
[Clear success criteria]
[What the solution should achieve]
[Include example of desired behavior]

## How to Start
1. Read: [specific files to review]
2. Run: [commands to see the problem]
3. Check: [related artifacts/docs]
4. Context: artifacts/context/[relevant].md

## Implementation Notes
- [Technical approach suggestions]
- [Potential solutions or patterns]
- [Known constraints or gotchas]
- [Relevant project edicts]

## Checklist
- [ ] [Specific implementation steps]
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Devlog entry created

## References
- Related: [TODO-NNN, PR#, commits]
- Artifacts: [sketches, analyses]
- External: [docs, library links]
```

Add entry to devlog: `**Issue Created**: TODO-YYYY-NNN_description.md`

Adapt template based on type:
- **Bugs**: Add reproduction steps, error messages
- **Features**: Add user stories, acceptance criteria
- **Refactoring**: Add migration plan, backwards compatibility
- **Tech Debt**: Add how incurred, remediation approach

Focus on capturing everything needed to resume work in the future.
