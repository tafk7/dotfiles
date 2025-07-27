# Documentation Redundancy Elimination Plan

## Overview
The current documentation has significant redundancy across 8 files. This plan consolidates to 5 focused files with clear separation of concerns.

## Files to Delete

### 1. ARTIFACTS.md
- **Reason**: Completely redundant with workflow.md
- **Action**: Delete entirely - all content exists in workflow.md

## Files to Merge

### 2. README.md + SLASH-README.md → README.md
- **Reason**: Both serve as entry points with 70% content overlap
- **New Structure**:
  ```
  # The Arete Framework
  ## Quick Start
  ## Philosophy
  ## Command Reference (consolidated from SLASH-README)
  ## Workflows
  ## Learn More
  ```

## Content to Remove

### 3. Workflow Examples
**Remove from**:
- BEST_PRACTICES.md (lines 177-196)
- README.md (lines 75-98) 
- SLASH-README.md (lines 217-246)
**Keep in**: workflow.md only

### 4. Command Format Details
**Remove from**:
- README.md (lines 146-167)
- COMMAND_CREATION.md (detailed format explanation)
**Keep in**: STANDARDS.md only
**Update**: COMMAND_CREATION.md to reference STANDARDS.md

### 5. Command Lists
**Remove from**:
- BEST_PRACTICES.md (lines 64-84)
- README.md (keep only categories, not full list)
**Keep in**: Merged README.md (from SLASH-README content)

### 6. Artifacts Workflow Details
**Remove from**:
- BEST_PRACTICES.md (lines 96-114)
**Keep in**: workflow.md only
**Update**: Add reference to workflow.md

## Final Documentation Structure

### Core Files (5)
1. **README.md** - Framework overview + command reference (merged)
2. **workflow.md** - Development process and artifacts workflow
3. **STANDARDS.md** - Command format specification
4. **BEST_PRACTICES.md** - Usage patterns and tips
5. **COMMAND_CREATION.md** - Guide for creating new commands

### Support Files (2)
6. **TEMPLATE.md** - Command template
7. **TEMPLATE_EXAMPLE.md** - Example command

## Key Principles
- Each concept documented in ONE authoritative location
- Other files reference, not duplicate
- Clear separation of concerns
- Reduced from ~500 lines of redundant content

## Implementation Order
1. Delete ARTIFACTS.md
2. Merge README.md and SLASH-README.md
3. Remove workflow examples from 3 files
4. Remove command format from 2 files
5. Clean up command lists
6. Add cross-references where content was removed

This reduces documentation by ~40% while improving clarity.