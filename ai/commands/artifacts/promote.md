---
descrption: Promote artifacts to production with full integration and verification
allowed-tools: Bash(cp:*), Bash(mv:*), Bash(mkdir:*), Bash(git:*), Bash(grep:*), ReadFile, WriteFile
---

# Promote Artifact

Move artifact from temporary workspace to production location with full integration.

## Context
- Target file: $ARGUMENTS
- File exists: !`test -f "$ARGUMENTS" && echo "Yes" || echo "No"`
- File type: !`file -b "$ARGUMENTS" 2>/dev/null || echo "Unknown"`
- Status prefix: !`basename "$ARGUMENTS" | grep -E "^(READY_|WIP_|BLOCKED_)" | cut -d_ -f1 || echo "none"`
- Modified: !`stat -c %y "$ARGUMENTS" 2>/dev/null | cut -d' ' -f1 || echo "Unknown"`

## Your Task

Execute promotion in three phases: **Analyze → Execute → Verify**

Each phase must complete successfully before proceeding to the next. Track all changes for potential rollback.

### PHASE 1: Analyze

**1.1 Validate Readiness**
- Confirm file exists and is readable
- Check for READY_ prefix (warn if missing)
- Scan for TODO/FIXME/HACK comments
- Review git history for recent changes
- Check if already promoted (look for metadata)

**1.2 Determine Destination**
Based on file type and content:

| Type | Pattern | Default Destination |
|------|---------|-------------------|
| Documentation | `*.md` in analyses/, designs/ | `docs/` (architecture/, api/, etc.) |
| Source Code | `*.py`, `*.js`, `*.ts` | `src/[module]/` based on imports |
| Tests | `test_*.py`, `*.test.js` | `tests/[module]/` |
| Config | `*.json`, `*.yaml` | Project root or `config/` |
| Assets | Images, data files | `assets/` or `public/` |

**1.3 Check for Conflicts**
- Does destination file exist?
- Are there naming conflicts?
- Will this break existing imports?
- Are there uncommitted changes?

Generate analysis report:
```
PROMOTION ANALYSIS: [filename]
============================
Status: [READY/NOT READY]
Type: [Code/Doc/Config/Asset]
Destination: [proposed path]
Conflicts: [none/file exists/naming]
Quality Issues: [N TODOs, N FIXMEs]
Dependencies: [list affected files]

[!] Warnings:
- [Any blocking issues]

Proceed? [Requires confirmation]
```

### PHASE 2: Execute

**2.1 Pre-flight Check**
Create dynamic checklist based on file type:

For **Code Files**:
```
[ ] No console.log/print debug statements
[ ] Imports use project conventions
[ ] Function/class names follow standards
[ ] Basic error handling present
[ ] No hardcoded test data
[ ] No exploration comments ("HACK", "TODO: clean up")
```

For **Documentation**:
```
[ ] Links use relative paths
[ ] Code examples are tested
[ ] Headers follow hierarchy
[ ] Metadata updated (if needed)
[ ] No references to artifacts/
```

For **Config Files**:
```
[ ] No development-only settings
[ ] Secrets use environment variables
[ ] Schema validates
[ ] Comments explain non-obvious settings
```

**2.2 Track Changes**
Before making any changes:
```bash
# Create promotion transaction log
echo "PROMOTION START: $(date)" > .promotion_log
echo "File: $ARGUMENTS" >> .promotion_log
echo "Destination: [destination]" >> .promotion_log
echo "Affected files:" >> .promotion_log
```

**2.3 Execute Promotion**

For **Documentation**:
1. Copy to destination
2. Update relative links
3. Add to doc index/TOC
4. Update cross-references

For **Code**:
1. Copy to destination with proper naming
2. Update import paths within file
3. Find and update imports in other files:
   ```bash
   # Find all potential imports
   grep -r "artifacts.*$(basename $FILE)" src/ tests/
   grep -r "from.*artifacts" --include="*.py" .
   grep -r "require.*artifacts" --include="*.js" .
   grep -r "import.*artifacts" --include="*.ts" .
   ```
4. Update module exports/index files
5. Run linter on promoted file
6. Run tests to verify nothing broke

### PHASE 3: Verify

**3.1 Run Verification**
Based on what was promoted:

For **Code**:
- Run test suite
- Check for import errors
- Verify linting passes
- Ensure no broken dependencies

For **Documentation**:
- Check all links work
- Verify images load
- Confirm formatting renders

**3.2 Update Records**

Add to devlog:
```markdown
## YYYY-MM-DD HH:MM - PROMOTED: [filename]
**From**: artifacts/[path]
**To**: [destination]
**Changes made**:
- [List each file modified]
- [Import updates made]
**Verification**: All tests pass
```

If artifact has frontmatter, add:
```yaml
promoted-to: [destination]
promoted-date: YYYY-MM-DD
```

**3.3 Cleanup**
After successful verification:
1. Remove original artifact (or move to `.artifacts_archive/`)
2. Update any TODO issues referencing this file
3. Commit all changes with message:
   ```
   Promote [filename] to production

   - Moved from artifacts/ to [destination]
   - Updated N import statements
   - All tests passing
   ```

### Rollback Procedure

If anything fails, use the promotion log:
```bash
# Review what was changed
cat .promotion_log

# Revert all changes
git checkout -- [affected files from log]

# Restore artifact if removed
git checkout -- [original artifact]

# Clean up log
rm .promotion_log
```

### Edge Cases

**File exists at destination**:
> Prompt: "Overwrite, merge, or rename?"
> If merge: Show diff first

**Breaking changes detected**:
> Create adapter layer or migration guide
> Document in devlog and TODO issue

**Import cycles created**:
> Detect before promotion
> Suggest refactoring to break cycle

**Exploration patterns remaining**:
> Global variables, hardcoded values
> Refactor during promotion, not after

### Remember

Promotion transforms quick explorations into production code. The artifact was created to learn; promotion requires care to integrate. Quality gates ensure exploration patterns don't pollute production.

This command embodies the Axiom of Standards: promoted code follows project conventions, not exploration shortcuts.
