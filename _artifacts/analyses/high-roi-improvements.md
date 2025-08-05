# High-ROI Improvement Plan: Dotfiles

## Executive Summary

Focus on deletions first - they're instant wins with zero risk. Then simplify what remains. Target 50% reduction in Week 1, another 20% in Week 2.

## Week 1: Pure Deletions (50% reduction, 2 hours work)

### Day 1: Clean House (30 minutes, -500+ lines)
```bash
# Delete all backup/old files
rm -f install.sh.old install.sh.stage2-backup
rm -f lib/packages.sh.old lib/backup.sh lib/wsl.sh
rm -f lib/validation-enhanced.sh
rm -f scripts/validate-install-enhanced.sh

# Delete unused scripts
rm -f scripts/cheatsheet.sh  # Already deleted
rm -f scripts/fr.sh          # Already deleted

# Clean git
git add -A && git commit -m "Delete backup files and incomplete refactoring attempts"
```
**Impact**: -8 files, -500+ lines, cleaner repo

### Day 2: Delete Validation Theater (45 minutes, -400 lines)
```bash
# Delete the entire validation framework
rm -f lib/validation.sh
rm -f scripts/validate-install.sh

# Remove validation sourcing from install.sh
# Delete these lines:
# - source "$DOTFILES_DIR/lib/validation.sh"
# - validate_installation (all calls)

git add -A && git commit -m "Delete validation theater - trust apt-get"
```
**Impact**: -2 files, -400 lines, simpler installation

### Day 3: Remove Duplicate Functions (30 minutes, -50 lines)
```bash
# In lib/core.sh:
# 1. Delete info() function (duplicate of log())
# 2. Delete command_exists() wrapper
# 3. Replace all command_exists calls with: command -v "$1" >/dev/null 2>&1

# In scripts/aliases/general.sh:
# Delete bat/fd compatibility aliases (lines 20-30)
# The symlinks in packages.sh already handle this
```
**Impact**: -50 lines, clearer code

### Day 4: Strip Vanity Features (30 minutes, -100 lines)
```bash
# Remove from install.sh:
# 1. All dry-run code (dry_run_exec function and DRY_RUN variable)
# 2. All emoji decorations (✅ ❌ ⚠️ ℹ️)
# 3. Phase structure - make it linear

# Remove from lib/core.sh:
# 1. All color variables except RED and NC
# 2. Success/error emoji functions
```
**Impact**: -100 lines, cleaner output

## Week 2: Simplifications (20% reduction, 2 hours work)

### Day 5: Inline Simple Wrappers (45 minutes, -80 lines)
```bash
# Replace throughout codebase:
safe_sudo apt-get install → sudo apt-get install
ensure_tool "git" → command -v git || sudo apt-get install -y git
safe_symlink → ln -sf (with [ -e check if needed])

# Delete wrapper functions from lib/core.sh
```
**Impact**: -80 lines, direct clarity

### Day 6: Consolidate WSL (30 minutes, -50 lines)
```bash
# Merge all WSL functionality into single file:
# scripts/functions/wsl.sh (keep this one)
# Delete: scripts/aliases/wsl.sh, scripts/env/wsl.sh
# Move any unique functions to the keeper
```
**Impact**: -2 files, -50 lines

### Day 7: Flatten Installation (45 minutes, -100 lines)
```bash
# Rewrite install.sh as simple sequential script:
#!/bin/bash
set -euo pipefail

# Source libraries
source lib/core.sh
source lib/packages.sh

# Update system
sudo apt-get update

# Install packages
sudo apt-get install -y "${base_packages[@]}"
[[ "$1" == "--work" ]] && install_work_packages
[[ "$1" == "--personal" ]] && install_personal_packages

# Link configs
for config in configs/*; do
    [[ -f "$config" ]] || continue
    target="$HOME/.${config##*/}"
    [[ -e "$target" ]] && mv "$target" "$target.bak"
    ln -sf "$PWD/$config" "$target"
done

echo "Installation complete"
```
**Impact**: -100+ lines, obvious flow

## Quick Wins Priority List

1. **Delete backup files** (5 min, -500 lines) ⚡
2. **Delete validation.sh** (10 min, -400 lines) ⚡
3. **Remove info() duplicate** (2 min, -10 lines) ⚡
4. **Delete dry-run mode** (15 min, -50 lines) ⚡
5. **Remove emojis** (10 min, -20 lines) ⚡

## What NOT to Touch (Yet)

1. **Theme system** - Users like it, works fine
2. **Package arrays** - Current structure is OK
3. **Config symlinks** - Current approach works
4. **Core logging** - Used everywhere, breaking change

## Success Metrics

- **Week 1**: From ~50KB to ~25KB (-50%)
- **Week 2**: From ~25KB to ~15KB (-70% total)
- **Time invested**: ~4 hours total
- **Risk**: Near zero (mostly deletions)
- **Clarity gain**: Immeasurable

## The One-Hour Challenge

If you only have one hour:
1. Delete all backup/old files (5 min)
2. Delete validation.sh (10 min)
3. Delete duplicate functions (10 min)
4. Remove dry-run mode (15 min)
5. Flatten install.sh (20 min)

Result: -1,000+ lines, 60% cleaner

## Remember

**Every deletion is a victory.** Start with the pure deletions - they're risk-free and deliver instant simplification. The best code is no code.

Arete.