# Slash Commands Guide

Quick reference for AI-powered development workflow commands. These commands help maintain code quality while adapting to different development scenarios.

## Core Workflow Commands

### `/sublime` - Code Quality Analysis
Analyze code against Perfect Code principles for comprehensive improvement recommendations.
```
/sublime                    # Analyze current directory
/sublime src/               # Analyze specific directory
/sublime --deep            # Deep analysis with dependency graphs
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_sublime_analysis.md`

### `/ship` - Emergency Delivery Mode
Get it working now, quality later. For hotfixes, demos, and deadlines.
```
/ship fix auth bug         # Ship a quick fix
/ship CRITICAL user data   # Critical priority
/ship demo feature         # Get demo working
```
**Creates**: Devlog entry + `TODO-YYMM-NNN` cleanup issue

### `/explore` - Experimentation Sandbox
Rapid experimentation without quality constraints. For trying ideas and learning.
```
/explore websocket implementation
/explore python async patterns
/explore react hooks approach
```
**Creates**: `artifacts/sketches/YYMMDD_HHMM_explore_[topic].[ext]`

### `/edict` - Compliance Checking
Verify code compliance with project constraints (edicts) defined in CLAUDE.md.
```
/edict                     # Check current directory
/edict src/auth           # Check specific path
/edict --dry-run          # Preview without changes
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_edict_compliance.md`

### `/context` - Build Mental Model
Deep analysis to establish comprehensive understanding before implementation.
```
/context                   # Analyze current directory
/context src/auth         # Analyze specific component
/context lib/parser       # Understand library structure
```
**Returns**: Comprehensive analysis in chat with mental model, navigation guide, and insights

### `/scribe` - Generate Documentation
Deep analysis followed by creation of permanent documentation with visual diagrams.
```
/scribe                    # Document current project
/scribe src/api           # Document API module
/scribe lib/auth          # Document authentication library
```
**Creates**: 1-5 files in `docs/` with README, architecture docs, and mermaid diagrams

### `/explain` - Deep Understanding Analysis
Perform deep analysis to understand and explain code/systems with educational focus.
```
/explain                   # Explain current directory
/explain src/auth.py      # Explain specific file
/explain lib/parser       # Explain component/library
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_explain_[target].md` with mental models, architecture diagrams, and navigation guides

## Artifact Management Commands

### `/artifacts/status` - Project Health Overview
Display comprehensive status of artifacts directory, open issues, and recent activity.
```
/artifacts/status          # Full status report
/artifacts/status issues   # Show only TODO items
/artifacts/status ready    # Show promotion-ready files
/artifacts/status old      # Show cleanup candidates
```

### `/artifacts/todo` - Create Tracked Issues
Generate comprehensive TODO issues with full context for future work.
```
/artifacts/todo implement user avatars
/artifacts/todo P0 fix payment processing bug
/artifacts/todo refactor auth system
```
**Creates**: `artifacts/issues/TODO-YYMM-NNN_description.md`

### `/artifacts/log` - Development Progress
Record progress in monthly devlog with quantified impact and artifact tracking.
```
/artifacts/log optimized database queries by 40%
/artifacts/log fixed auth bug affecting 2FA
/artifacts/log researched caching strategies
```
**Updates**: `artifacts/devlog_YYMM.md`

### `/artifacts/promote` - Move to Production
Promote validated artifacts from temporary workspace to production locations.
```
/artifacts/promote artifacts/READY_auth_module.py
/artifacts/promote artifacts/designs/api_v2.md
```
**Moves**: Artifact to appropriate production directory (src/, docs/, etc.)

### `/artifacts/cleanup` - Remove Old Artifacts
Clean up stale artifacts while preserving important files and references.
```
/artifacts/cleanup         # Remove files >30 days old
/artifacts/cleanup 14      # Remove files >14 days old
/artifacts/cleanup --dry-run   # Preview without removing
```

### `/cleanup` - Post-Implementation Polish
Analyze code for dead weight, redundancy, and artifacts to polish for release.
```
/cleanup                   # Analyze current directory
/cleanup src/feature       # Analyze specific path
/cleanup src/ --aggressive # Feature branch cleanup
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_cleanup_analysis.md`

## Quality Philosophy Spectrum

Commands represent different quality levels for different scenarios:

```
EXPLORE ←────────────────────────────────────→ SUBLIME
No quality          Balanced            Perfect quality
constraints         approach            standards

/explore            /artifacts/*         /sublime
/ship               /context             /edict
                    /scribe              
                    /explain
                    /cleanup
```

## Workflow Example

```bash
# 1. Build understanding first
/context src/feature

# 2. Deep dive when needed
/explain src/complex_module

# 3. Start with exploration
/explore new feature idea

# 4. If promising, create TODO
/artifacts/todo implement feature properly

# 5. When urgent, ship it
/ship hotfix for production bug

# 6. Log progress
/artifacts/log shipped emergency fix, created cleanup TODO

# 7. Polish before review
/cleanup src/hotfix

# 8. Later, analyze quality
/sublime src/hotfix

# 9. Document important modules
/scribe src/core

# 10. Check status regularly
/artifacts/status

# 11. Promote when ready
/artifacts/promote artifacts/READY_feature.py

# 12. Clean up periodically
/artifacts/cleanup --dry-run
```

## File Naming Conventions

- **Timestamps**: `YYMMDD_HHMM_description.ext`
- **TODO Issues**: `TODO-YYMM-NNN_description.md`
- **Devlog**: `artifacts/devlog_YYMM.md`
- **Status Prefixes**: `READY_`, `WIP_`, `BLOCKED_`

## Directory Structure

```
artifacts/
├── devlog_YYMM.md      # Monthly progress log
├── issues/             # TODO-YYMM-NNN files
├── analyses/           # Sublime & edict reports
├── designs/            # Architecture proposals
├── sketches/           # Exploration experiments
├── reference/          # Permanent project references
└── checklists/         # Complex task tracking
```

## Best Practices

1. **Use `/explore` freely** - No judgment in exploration mode
2. **Create TODOs proactively** - Capture all technical debt
3. **Log progress daily** - Maintain momentum visibility
4. **Run `/artifacts/status` weekly** - Stay aware of project health
5. **Ship when needed** - Perfect is the enemy of done
6. **Analyze with `/sublime` regularly** - Continuous improvement
7. **Clean up monthly** - Keep artifacts manageable

## Command Context

Each command gathers dynamic context using shell expressions (`!` prefix) to understand:
- Current directory and git status
- Existing artifacts and issues
- File ages and references
- Build/test status

This ensures commands adapt intelligently to your project state.