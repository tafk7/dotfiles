---
description: Show current artifacts, open issues, and recent activity
---

# Artifacts Status  

Display comprehensive status of artifacts directory including active work and open issues.

Filter: $ARGUMENTS (e.g., "issues", "ready", "old", or file pattern)

## Task

<task>Generate artifacts status report${ARGUMENTS:+ for: $ARGUMENTS}</task>

<requirements>
1. Show open issues and their priority
2. Identify files ready for promotion
3. Flag cleanup candidates and problems
4. Provide actionable next steps
</requirements>

<phases>
1. **Scan** - Inventory artifacts
2. **Analyze** - Categorize by status
3. **Report** - Show actionable summary
</phases>

<output>
Terminal output (status report with action items)
</output>

<conditional>
If "issues": Focus on TODO files
If "ready": Show READY_ files
If "old": Show cleanup candidates
</conditional>

<error-handling>
Missing artifacts directory: Create and report
No matching files: Show helpful examples
</error-handling>

Clear visibility enables decisive action - status illuminates the path forward.