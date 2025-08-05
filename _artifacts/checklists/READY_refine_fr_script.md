# Find & Replace Script Refinement Checklist

## Current Analysis

The script provides basic find/replace functionality but lacks safety features, file filtering, and proper error handling.

### Strengths
- Simple and focused purpose
- Shows matches before replacing
- Requires user confirmation
- Uses Perl for reliable regex escaping

### Weaknesses
- No file type filtering (could modify binaries)
- No backup before modification
- No dry-run option
- Limited feedback on what was changed
- No exclusion patterns (e.g., .git directories)

## Refinement Checklist

### 1. Add Safety Features (High Impact, Low Risk)

**Implementation Steps:**
- [ ] Add file type filtering to avoid binary files
- [ ] Exclude version control directories by default
- [ ] Add backup option before modifications

```bash
# Add after line 10:
EXCLUDE_DIRS=".git .svn node_modules .backups"
FILE_TYPES="${FILE_TYPES:-}"  # Allow override via environment

# Replace line 13 with safer grep:
grep -rn --color=always -F "$OLD_STRING" "$TARGET_DIR" \
  --exclude-dir={.git,.svn,node_modules,.backups} \
  --exclude="*.{jpg,png,gif,pdf,zip,tar,gz}" || echo "No occurrences found."
```

### 2. Add Dry-Run Mode (High Impact, Low Risk)

**Implementation Steps:**
- [ ] Add --dry-run flag support
- [ ] Show what would be changed without modifying files

```bash
# Add argument parsing:
DRY_RUN=false
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    *) break ;;
  esac
done

# Modify replacement logic:
if [[ "$DRY_RUN" == "true" ]]; then
  echo "DRY RUN: Would replace in these files:"
  grep -l -F "$OLD_STRING" "$TARGET_DIR" --exclude-dir={.git,.svn,node_modules}
else
  # Actual replacement
fi
```

### 3. Add Progress Feedback (Medium Impact, Low Risk)

**Implementation Steps:**
- [ ] Count affected files before replacement
- [ ] Show progress during replacement
- [ ] Summary of changes after completion

```bash
# Before replacement:
FILE_COUNT=$(grep -l -F "$OLD_STRING" "$TARGET_DIR" --exclude-dir={.git,.svn,node_modules} | wc -l)
echo "Will modify $FILE_COUNT files"

# After replacement:
echo "✓ Replaced '$OLD_STRING' with '$NEW_STRING' in $FILE_COUNT files"
```

### 4. Add Backup Creation (Medium Impact, Low Risk)

**Implementation Steps:**
- [ ] Create timestamped backup of modified files
- [ ] Store in .backups directory
- [ ] Add --no-backup flag for power users

```bash
# Add backup function:
backup_files() {
  local backup_dir="$DOTFILES_DIR/.backups/fr_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"
  
  grep -l -F "$OLD_STRING" "$TARGET_DIR" --exclude-dir={.git,.svn,node_modules} | \
    while read -r file; do
      cp --parents "$file" "$backup_dir/"
    done
  
  echo "Backups created in: $backup_dir"
}
```

### 5. Add Interactive Mode (Low Impact, Medium Risk)

**Implementation Steps:**
- [ ] Add --interactive flag
- [ ] Show each match in context
- [ ] Allow per-file confirmation

```bash
# Add to argument parsing:
INTERACTIVE=false
case $1 in
  --interactive) INTERACTIVE=true; shift ;;
esac

# In replacement section:
if [[ "$INTERACTIVE" == "true" ]]; then
  # Show each file with context and ask for confirmation
fi
```

## Implementation Priority

1. **Safety Features** - Implement first to prevent accidental damage
2. **Dry-Run Mode** - Essential for testing before actual changes
3. **Progress Feedback** - Improves user experience
4. **Backup Creation** - Additional safety net
5. **Interactive Mode** - Nice-to-have for selective replacements

## Testing Checklist

- [ ] Test with binary files present (should skip them)
- [ ] Test in git repository (should skip .git directory)
- [ ] Test dry-run mode shows correct files
- [ ] Test backup creation and restoration
- [ ] Test with special characters in search string
- [ ] Test with empty/whitespace replacement string

## Quick Wins

The first three improvements can be implemented in under 30 lines of code while significantly improving safety and usability. Focus on these for maximum impact with minimal risk.