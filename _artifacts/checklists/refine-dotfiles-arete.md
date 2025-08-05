# Refinement Checklist: Dotfiles Arete Simplification

Based on the Arete review, here are 5 high-impact, low-risk improvements to move toward true simplicity.

## Priority 1: Merge Duplicate Validation Systems (High Impact, Low Risk)
**Impact**: Remove 400+ lines of redundancy
**Risk**: Low - pick one and delete the other

### Implementation Steps:
- [ ] Delete `lib/validation-enhanced.sh` (420 lines removed)
- [ ] Delete `scripts/validate-install-enhanced.sh` (103 lines removed)
- [ ] Update documentation to reference only `validate-install.sh`
- [ ] Test: Run `./scripts/validate-install.sh` to ensure it still works

**Rationale**: Two validation systems = 0 validation systems. Pick one.

## Priority 2: Collapse Modular Files Back to Core (High Impact, Low Risk)
**Impact**: Remove 200 lines and 2 unnecessary files
**Risk**: Low - functions only used through core.sh anyway

### Implementation Steps:
- [ ] Copy essential functions from `backup.sh` to `core.sh`:
  - `backup_file()` 
  - `safe_symlink()`
  - Delete the rest (unused complexity)
- [ ] Copy essential functions from `wsl.sh` to `core.sh`:
  - `is_wsl()`
  - `get_windows_username()` (simplified to 3 lines)
  - `setup_wsl_clipboard()`
- [ ] Update `core.sh` to remove source statements
- [ ] Delete `lib/backup.sh` and `lib/wsl.sh`
- [ ] Test: Run install.sh to verify nothing breaks

**Rationale**: These were never independent modules, just arbitrary splits.

## Priority 3: Simplify Package Management (Medium Impact, Low Risk)
**Impact**: Clearer, more maintainable package lists
**Risk**: Low - just reorganizing data

### Implementation Steps:
- [ ] Convert packages.sh to use simple text files:
  ```bash
  # packages/base.txt
  curl
  wget
  git
  zsh
  neovim
  
  # packages/work.txt
  docker.io
  nodejs
  ```
- [ ] Update install function to read from files:
  ```bash
  install_packages() {
      local file="$1"
      xargs -a "$file" sudo apt-get install -y
  }
  ```
- [ ] Test: Verify package installation still works

**Rationale**: Data in data files, not code.

## Priority 4: Remove Feature Creep from Install.sh (Medium Impact, Low Risk)
**Impact**: Simpler, clearer installation flow
**Risk**: Low - removing unused complexity

### Implementation Steps:
- [ ] Remove JSON output code (never needed for dotfiles)
- [ ] Remove category tracking in validation
- [ ] Simplify phase functions to inline code where it's just 2-3 lines
- [ ] Remove CONFIG_MAP associative array - just use a simple loop
- [ ] Test: Run `./install.sh --dry-run` to verify

**Rationale**: Features that sound good but add no value.

## Priority 5: Create Single Validation Function (Medium Impact, Medium Risk)
**Impact**: Replace 400-line validation with 50-line function
**Risk**: Medium - need to ensure we catch real issues

### Implementation Steps:
- [ ] Create simple `validate()` function in core.sh:
  ```bash
  validate() {
      local fail=0
      # Essential commands
      for cmd in git curl zsh nvim; do
          command -v $cmd >/dev/null || { echo "Missing: $cmd"; ((fail++)); }
      done
      # Essential files  
      for file in ~/.bashrc ~/.zshrc ~/.gitconfig; do
          [[ -e $file ]] || { echo "Missing: $file"; ((fail++)); }
      done
      [[ $fail -eq 0 ]] && success "Valid" || error "$fail issues"
  }
  ```
- [ ] Replace complex validation with this simple check
- [ ] Delete standalone validation script (use function instead)
- [ ] Test: Ensure validation catches real issues

**Rationale**: 50 lines of reality beats 400 lines of abstraction.

## Quick Wins Summary

1. **Delete validation-enhanced.sh**: -520 lines, 5 minutes
2. **Merge backup/wsl into core**: -200 lines, 15 minutes  
3. **Package lists as text files**: Cleaner structure, 20 minutes
4. **Remove install.sh features**: -100 lines, 15 minutes
5. **Simple validation function**: -350 lines, 30 minutes

**Total Impact**: ~1,170 lines removed (85% reduction)
**Total Time**: ~90 minutes
**Risk Level**: Low to Medium

## Success Criteria

After these refinements:
- `lib/` should have 2-3 files max (core.sh, packages.sh)
- Total lib/ lines should be under 400 (from 1,361)
- No duplicate functionality
- No "enhanced" versions
- Every line serves a clear, essential purpose

## Not Included (Too Risky/Low Impact)

- Removing dry-run mode (actually useful)
- Changing install flow drastically (works fine)
- Removing all validation (some checking is good)
- Rewriting from scratch (unnecessary)

Focus on deletion and simplification, not reorganization.