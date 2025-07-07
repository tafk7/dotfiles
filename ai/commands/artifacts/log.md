---
description: Log development progress with automatic milestone detection
---

# Log Progress

Record: $ARGUMENTS

## Task

<task>Log progress for: $ARGUMENTS</task>

<requirements>
1. Add entry to artifacts/devlog_YYMM.md
2. Quantify real impact (lines, performance, bugs)
3. Link recent artifacts and issues
4. Mark milestones for major achievements
</requirements>

<phases>
1. **Document** - Write structured entry with impact
2. **Link** - Connect artifacts and issues
3. **Review** - Check for milestone achievements
</phases>

<output>
Append to artifacts/devlog_YYMM.md
</output>

<conditional>
If no devlog exists: Create with header
If major achievement: Add milestone marker
</conditional>

<error-handling>
Missing devlog: Create new file
No recent work: Note planning/research phase
</error-handling>

Real impact compounds - every honest entry builds momentum toward perfection.