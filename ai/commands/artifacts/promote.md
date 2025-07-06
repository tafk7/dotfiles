---
description: Promote artifacts to production with full integration and verification
---

# Promote Artifact

Move artifact from temporary workspace to production location with full integration.

## Context
- Target: $ARGUMENTS
- Exists: !`test -f "$ARGUMENTS" && echo "Yes" || echo "No"`
- Type: !`file -b "$ARGUMENTS" 2>/dev/null || echo "Unknown"`
- Status: !`basename "$ARGUMENTS" | grep -E "^(READY_|WIP_|BLOCKED_)" | cut -d_ -f1 || echo "none"`

## Task

<task>Promote $ARGUMENTS to production</task>

<phases>
### Phase 1: Analyze
1. Validate readiness (check READY_ prefix, scan for TODOs)
2. Determine destination by file type
3. Check for conflicts and dependencies

### Phase 2: Execute  
1. Run pre-flight checklist
2. Copy to destination
3. Update all imports and references
4. Run tests/linting

### Phase 3: Verify
1. Confirm all tests pass
2. Update devlog with promotion record
3. Clean up original artifact
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

<checklist>
**Code Files:**
- [ ] No debug statements
- [ ] Proper imports
- [ ] Error handling
- [ ] No hardcoded data

**Documentation:**
- [ ] Relative links
- [ ] No artifacts/ refs
- [ ] Tested examples
</checklist>

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

Quality gates ensure exploration patterns don't pollute production.