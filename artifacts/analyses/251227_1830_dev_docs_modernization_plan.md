# Dev Documentation Modernization Plan

## Executive Summary

The ai/dev/ documentation is significantly outdated, reflecting an earlier, more complex version of the command system. The current implementation has evolved to be much simpler, following the "Trust the AI" philosophy with standardized 3-tag format and artifacts-based workflow.

## Modernization Strategy

### Phase 1: Immediate Fixes (Critical)

1. **Update TEMPLATE.md**
   - Replace with actual current format
   - Include YAML frontmatter
   - Add real command as example
   - Keep it minimal and clear

### Phase 2: Core Documentation Updates

2. **Rewrite STANDARDS.md**
   - Focus only on current 3-tag format
   - Remove all obsolete sections
   - Add section on YAML frontmatter
   - Include naming conventions

3. **Modernize BEST_PRACTICES.md**
   - Remove obsolete features (sandbox, hooks, MCP)
   - Update command location to ai/commands/
   - Simplify prompting guidelines
   - Add artifacts workflow section
   - Include real examples from current system

### Phase 3: Comprehensive Reference

4. **Update SLASH-README.md**
   - Remove non-existent commands
   - Add all current commands with accurate descriptions
   - Update format examples to match current
   - Organize by command categories
   - Simplify workflow examples

5. **Enhance README.md**
   - Complete command inventory
   - Add quick start guide
   - Link to other docs appropriately
   - Keep philosophy but add practical usage

### Phase 4: New Documentation

6. **Create ARTIFACTS.md**
   - Explain artifacts workflow in detail
   - Document temporal naming convention
   - Show promotion workflow (READY_*, BLOCKED_*)
   - Include issue tracking format

7. **Create COMMAND_CREATION.md**
   - Step-by-step guide for new commands
   - When to create vs use existing
   - Testing commands
   - Integration with devlog

## Implementation Order

1. **Week 1**: Phase 1 (Templates)
   - Fix TEMPLATE.md first (foundation for everything else)

2. **Week 2**: Phase 2 (Core Updates)
   - Update STANDARDS.md and BEST_PRACTICES.md
   - These guide all other documentation

3. **Week 3**: Phase 3 (References)
   - Comprehensive update of SLASH-README.md
   - Polish README.md

4. **Week 4**: Phase 4 (New Docs)
   - Add missing documentation for new concepts

## Key Principles for Updates

1. **Simplicity First**: Current system is simpler than documented
2. **Real Examples**: Use actual commands from ai/commands/
3. **Trust the AI**: Avoid prescriptive, step-by-step approaches
4. **Artifacts Central**: Emphasize artifacts workflow throughout
5. **Format Consistency**: All examples must use current 3-tag format

## Success Metrics

- New user can create a working command in 10 minutes
- Documentation matches 100% of current commands
- No references to obsolete features
- Examples work without modification

## Quick Wins

Start with TEMPLATE.md - it's the most wrong and easiest to fix. This immediately helps anyone trying to create new commands.

## Long-term Vision

The modernized documentation should reflect the elegant simplicity of the current system, making it obvious why the evolution happened and how to work within the new paradigm.

Arete!