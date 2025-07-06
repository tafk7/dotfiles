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
### Phase 1: Analyze
1. Validate readiness (READY_ prefix, no TODOs)
2. Determine destination by file type
3. Check conflicts and dependencies

### Phase 2: Execute  
1. Run pre-flight checklist:
   - No debug code or console.logs
   - Proper error handling
   - Tests pass
   - Documentation accurate
2. Copy to destination with imports update
3. Run tests/linting

### Phase 3: Verify
1. Confirm all tests pass
2. Update devlog with promotion
3. Clean up original
</phases>

<destinations>
| Type | Pattern | Destination |
|------|---------|-------------|
| Docs | *.md | docs/ |
| Code | *.py/js/ts | src/[module]/ |
| Tests | test_*, *.test.* | tests/ |
| Config | *.json/yaml | root or config/ |
| Assets | images, data | assets/ |
</destinations>

<conditional>
If code file:
- Run type checking
- Verify test coverage
- Check import paths

If documentation:
- Update relative links
- Verify examples work
- Check formatting

If config file:
- Validate schema
- Check env variables
- Test in isolation
</conditional>


<output>
```
PROMOTION ANALYSIS: [filename]
============================
Status: READY
Destination: [path]
Conflicts: [none/exists]
Issues: [N TODOs]

Proceed? (yes/no)
```

After promotion:
1. Log in devlog_YYMM.md
2. Update imports across codebase
3. Commit with descriptive message
</output>

<rollback>
If promotion fails:
- Use git to revert changes
- Restore original artifact
- Document failure reason
</rollback>

# File type specific checks integrated into conditionals above:
# - Code: test suite, imports, types
# - Docs: links, examples, formatting
# - Config: schema, env vars, compatibility
# - Assets: optimization, naming, structure

Promotion transforms experiments into production excellence - quality gates protect The Sublime.