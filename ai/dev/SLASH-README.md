# Slash Commands Guide

Quick reference for AI-powered development workflow commands. These commands help maintain code quality while adapting to different development scenarios.

## Core Workflow Commands

### `/arete` - Code Quality Analysis
Analyze code against Perfect Code principles for comprehensive improvement recommendations.
```
/arete                      # Analyze current directory
/arete src/                 # Analyze specific directory
/arete --deep              # Deep analysis with dependency graphs
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_arete_analysis.md`

### `/ship` - Emergency Delivery Mode
Get it working now, quality later. For hotfixes, demos, and deadlines.
```
/ship fix auth bug         # Ship a quick fix
/ship CRITICAL user data   # Critical priority
/ship demo feature         # Get demo working
```
**Creates**: Devlog entry + `TODO-YYMM-NNN` cleanup issue

### `/refine` - Incremental Improvement
Analyze code and provide actionable improvement recommendations with implementation checklist.
```
/refine                    # Refine current directory
/refine src/auth          # Refine specific component
/refine --focus complexity # Focus on complexity reduction
```
**Creates**: `artifacts/checklists/YYMMDD_HHMM_refine_checklist.md`

### `/architect` - System Design
Design component structure and key architectural decisions for new systems.
```
/architect user-auth-service   # Design new microservice
/architect payment-flow        # Design new feature
/architect dashboard-app       # Design new application
```
**Creates**: `artifacts/designs/YYMMDD_HHMM_architecture_[system].md`

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
/artifacts/cleanup         # Remove files >14 days old
/artifacts/cleanup 7       # Remove files >7 days old
/artifacts/cleanup --dry-run   # Preview without removing
```

### `/profile` - Performance Investigation
Analyze performance characteristics to identify bottlenecks and optimization opportunities.
```
/profile                   # Profile current directory
/profile src/api          # Profile specific component
/profile --memory          # Focus on memory analysis
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_performance_analysis.md`

### `/cleanup` - Post-Implementation Polish
Analyze code for dead weight, redundancy, and artifacts to polish for release.
```
/cleanup                   # Analyze current directory
/cleanup src/feature       # Analyze specific path
/cleanup src/ --aggressive # Feature branch cleanup
```
**Creates**: `artifacts/analyses/YYMMDD_HHMM_cleanup_analysis.md`

### `/checklist` - Implementation Checklist
Generate actionable step-by-step implementation checklist from plans.
```
/checklist                 # From current conversation
/checklist plan.md         # From specific plan file
/checklist artifacts/analyses/design.md  # From analysis
```
**Creates**: `artifacts/checklists/YYMMDD_HHMM_checklist_[description].md`

### `/implement` - Execute Checklist
Execute checklist items with real-time progress tracking and devlog updates.
```
/implement artifacts/checklists/auth_checklist.md  # Execute full checklist
/implement checklist.md Phase 1-3                 # Execute specific phases
/implement plan.md --dry-run                       # Preview execution
```
**Updates**: Checklist file with progress + devlog entry

### `/git/commit` - Generate Commit Messages
Analyze staged changes to generate descriptive commit message based solely on content.
```
/git/commit                # Generate message for staged changes
/git/commit --amend       # Generate message for amending last commit
```
**Returns**: Executable git command with appropriate commit message

### `/git/diff` - Summarize Changes
Analyze unstaged changes since last commit and provide summary of modifications.
```
/git/diff                  # Summarize unstaged changes
/git/diff --staged        # Include staged changes
/git/diff src/auth        # Changes in specific area
```
**Returns**: Clear summary of what changed, grouped by component

## Quality Philosophy Spectrum

Commands represent different code quality approaches for different scenarios:

```
EXPLORE ←────────────────────────────────────→ ARETE
Speed over          Balanced             Quality over
quality            improvement           speed

/explore            /refine              /arete
/ship               /cleanup             /edict
                    /profile             
```

**Supporting Commands** (quality-neutral):
- `/architect` - System design (pre-code)
- `/context` - Understanding (analysis)
- `/scribe` - Documentation (post-code)
- `/explain` - Learning (educational)
- `/artifacts/*` - Project management
- `/git/*` - Version control assistance

## Workflow Example

```bash
# 1. Design new systems first
/architect notification-service

# 2. Build understanding of existing code
/context src/feature

# 3. Start with exploration
/explore new feature idea

# 4. If promising, create TODO
/artifacts/todo implement feature properly

# 5. Refine incrementally
/refine src/feature

# 6. When urgent, ship it
/ship hotfix for production bug

# 7. Log progress
/artifacts/log shipped emergency fix, created cleanup TODO

# 8. Profile performance if needed
/profile src/hotfix

# 9. Polish before review
/cleanup src/hotfix

# 10. Later, analyze quality
/arete src/hotfix

# 11. Document important modules
/scribe src/core

# 12. Check changes before commit
/git/diff

# 13. Generate commit message
/git/commit

# 14. Check status regularly
/artifacts/status

# 15. Promote when ready
/artifacts/promote artifacts/READY_feature.py

# 16. Clean up periodically
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
├── analyses/           # Arete & edict reports
├── designs/            # Architecture proposals
├── sketches/           # Exploration experiments
├── reference/          # Permanent project references
└── checklists/         # Complex task tracking
```

## Command Arguments Reference

### Core Commands

**`/arete`** - Code quality analysis
- No args: Analyze current directory
- `path`: Analyze specific directory or file
- `--deep`: Enable deep analysis with dependency graphs and metrics

**`/ship`** - Emergency delivery mode
- `task description`: What needs to be shipped (e.g., "fix auth bug")
- `CRITICAL/URGENT/ASAP task`: Triggers maximum speed mode
- Examples: "hotfix payment", "CRITICAL data loss", "demo feature"

**`/explore`** - Experimentation sandbox
- `topic/question`: What to explore (language auto-detected)
- Examples: "websocket implementation", "python async", "react hooks"

**`/edict`** - Compliance checking
- No args: Check current directory
- `path`: Check specific file or directory
- `--dry-run`: Preview without making changes

**`/context`** - Build mental model
- No args: Analyze current directory
- `path`: Analyze specific component/directory
- Examples: "src/auth", "lib/parser"

**`/scribe`** - Generate documentation
- No args: Document current project
- `path`: Document specific module/directory
- `--update`: Refresh existing documentation
- `--output path`: Custom output location

**`/explain`** - Deep understanding
- No args: Explain current directory
- `file`: Explain specific file
- `directory`: Explain component/library
- `topic`: Explain concept

**`/refine`** - Incremental improvement
- No args: Analyze current directory
- `path`: Analyze specific file/directory
- `--focus [area]`: Specific refinement focus

**`/profile`** - Performance investigation
- No args: Profile current directory
- `path`: Analyze specific file/directory
- `--memory`: Focus on memory usage patterns
- `--cpu`: Focus on computational bottlenecks

**`/architect`** - System design
- `system-name`: Design new system/service/feature
- No args: Design architecture for current directory context

**`/cleanup`** - Post-implementation polish
- No args: Analyze current directory
- `path`: Analyze specific path
- `--aggressive`: Feature branch cleanup mode

**`/checklist`** - Implementation checklist
- No args: Generate from current conversation
- `file path`: Generate from plan file
- Examples: "plan.md", "artifacts/analyses/design.md"

**`/implement`** - Execute checklist
- `checklist-path`: Required path to checklist file
- `Phase 1-3` or `Quick Wins`: Execute specific phases only
- `--dry-run`: Preview execution without changes

### Artifact Commands

**`/artifacts/status`** - Project health
- No args: Full status report
- `issues`: Show only TODO items
- `ready`: Show promotion-ready files
- `old`: Show cleanup candidates

**`/artifacts/todo`** - Create issues
- `description`: Issue description
- `P0/P1/P2 description`: Set priority
- Examples: "implement avatars", "P0 fix payment bug"

**`/artifacts/log`** - Record progress
- `progress description`: What was accomplished
- Include metrics when possible (%, lines, bugs)
- Examples: "optimized queries by 40%", "fixed 2FA bug"

**`/artifacts/promote`** - Move to production
- `file path`: Artifact to promote (must have READY_ prefix)
- File type determines destination automatically

**`/artifacts/cleanup`** - Remove old artifacts
- No args: Remove files >14 days old
- `number`: Remove files >N days old
- `--dry-run`: Preview without removing

### Git Commands

**`/git/commit`** - Generate commit messages
- No args: Analyze all staged changes
- `--amend`: Generate message for amending last commit

**`/git/diff`** - Summarize changes
- No args: Show unstaged changes
- `--staged`: Include staged changes
- `file/path`: Show changes for specific area

## Best Practices

1. **Use `/explore` freely** - No judgment in exploration mode
2. **Create TODOs proactively** - Capture all technical debt
3. **Log progress daily** - Maintain momentum visibility
4. **Run `/artifacts/status` weekly** - Stay aware of project health
5. **Ship when needed** - Perfect is the enemy of done
6. **Analyze with `/arete` regularly** - Continuous improvement
7. **Clean up monthly** - Keep artifacts manageable

## Command Context

Each command gathers dynamic context using shell expressions (`!` prefix) to understand:
- Current directory and git status
- Existing artifacts and issues
- File ages and references
- Build/test status

This ensures commands adapt intelligently to your project state.