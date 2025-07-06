---
description: Promote artifacts to production with full integration and verification
---

# Promote Artifact

Move artifact from temporary workspace to production location with full integration.

## Context
- Target: $ARGUMENTS
- Exists: !`test -f "$ARGUMENTS" && echo "Yes" || echo "No"`
- Type: !`file -b "$ARGUMENTS" 2>/dev/null || echo "Unknown"`
- Status: !`basename "$ARGUMENTS" | grep -E "^(READY_|WIP_|BLOCKED_)" | cut -d_ -f1 || echo "UNPREFIXED"`
- Size: !`test -f "$ARGUMENTS" && du -h "$ARGUMENTS" | cut -f1 || echo "N/A"`
- TODOs: !`test -f "$ARGUMENTS" && grep -c "TODO" "$ARGUMENTS" 2>/dev/null || echo "0"`
- Age: !`test -f "$ARGUMENTS" && echo $(( ($(date +%s) - $(stat -c %Y "$ARGUMENTS" 2>/dev/null || echo 0)) / 86400 )) || echo "N/A"` days

## Task

<task>Promote $ARGUMENTS to production</task>

<phases>
1. **Analyze** - Validate readiness, determine destination, check conflicts
2. **Execute** - Run pre-flight checklist, copy with import updates, test
3. **Verify** - Confirm tests pass, update devlog, clean up original
</phases>

<conditional>
Destinations: Docs(*.md)→docs/ | Code(*.py/js/ts)→src/ | Tests→tests/ | Config→root/config/ | Assets→assets/
Type checks: Code(types,coverage,imports) | Docs(links,examples,format) | Config(schema,env,isolation) | Assets(optimize,naming,structure)
Pre-flight: No debug code, proper error handling, tests pass, docs accurate
</conditional>


<output>
```
PROMOTION ANALYSIS: [filename]
Status: READY | Destination: [path] | Conflicts: [none/exists] | Issues: [N TODOs]

Proceed? (yes/no)
```

After promotion: Log in devlog, update imports, commit with message
If fails: Git revert, restore artifact, document reason
</output>

<error-handling>
File not found: List available READY_ files as suggestions
Permission denied: Check file ownership and permissions
Target exists: Prompt for overwrite confirmation
Invalid path: Suggest correct destination based on file type
No READY_ prefix: Remind about workflow requirements
</error-handling>

Promotion transforms experiments into production excellence - quality gates protect The Sublime.