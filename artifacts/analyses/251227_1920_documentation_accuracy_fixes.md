# Documentation Accuracy Fixes Needed

## Critical Issues

### 1. Missing Commands in README.md
**Missing from command reference:**
- `/git:diff` - Analyze changes and implications
- `/hone` - Clean and optimize existing code  
- `/artifacts/log` - Append to development log
- `/artifacts/promote` - Move artifacts to production
- `/artifacts/cleanup` - Remove old artifacts

### 2. Format Inconsistency
**Issue**: Documentation says all commands follow 3-tag format, but `/git:commit` uses different structure
**Action**: Either update `/git:commit` to match standard format OR document exceptions

### 3. Directory Structure in STANDARDS.md
**Current (lines 87-98)**:
```
ai/commands/
├── architect.md         # Design commands
├── arete.md            # Quality analysis
├── ship.md             # Fast delivery
├── artifacts/          # Artifact management
│   ├── status.md
│   └── todo.md
└── git/               # Git operations
    ├── commit.md
    └── diff.md
```

**Should show all files** or use "..." to indicate more files exist

### 4. TODO Format Specificity
`/ship` command says "Create cleanup issue in artifacts/" but workflow.md specifies exact format `TODO-YYMM-NNN_[description].md`

## Minor Issues

### 5. Duplicate in COMMAND_CREATION.md
Lines 221-222 repeat "Clear output location specified"

### 6. Command Counts
While "20 commands" is technically correct, the incomplete listings make this misleading

## Recommendations

1. **Update README.md** to include all 20 commands properly categorized
2. **Review `/git:commit`** format - either update command or document why it's different
3. **Fix directory examples** to match actual structure
4. **Align TODO format** documentation across files
5. **Remove duplicate** checklist item