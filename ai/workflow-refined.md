# workflow.md - Development Workflow v2.0

*This document defines the development process. For philosophy, see global CLAUDE.md. For project-specific configuration, see your project's CLAUDE.md.*

## Directory Structure

```
project/
├── artifacts/               # Temporary development work
│   ├── devlog_YYMM.md       # Monthly development log
│   ├── issues/              # TODO tracking with full context
│   ├── analyses/            # Code analyses (human-facing)
│   ├── designs/             # Architecture proposals
│   ├── sketches/            # Quick experiments
│   ├── context/             # AI reference (permanent)
│   ├── tests/               # Experimental tests
│   ├── checklists/          # Task tracking (NEW)
│   └── output/              # Generated artifacts
├── src/                     # Production code
├── tests/                   # Production tests
├── docs/                    # Permanent documentation
└── .claude/                 # Claude Code configuration
    └── commands/            # Custom slash commands
```

## Core Principles

### Temporal Artifacts
Everything in `artifacts/` is temporary experimentation toward The Sublime. Production code lives in `src/`, `tests/`, and `docs/`.

### Timestamp Convention
All artifact files use: `YYMMDD_HHMM_description.ext`
- Example: `241215_1430_auth_refactoring.md`
- Optional status markers: `WIP_`, `READY_`, `BLOCKED_`, `DEPRECATED_`

### Development Log
Track progress in `artifacts/devlog_YYMM.md`:
- Daily entries with task, impact, and artifacts created
- Clara adds milestones for significant achievements
- Links to issues created and code promoted
- Structured format for easy parsing:
  ```markdown
  ## YYYY-MM-DD HH:MM - [Task Type]: [Description]
  **Impact**: [What changed]
  **Artifacts**: [Files created/modified]
  **Next**: [Follow-up actions]
  ```

Progress updates use this format:
```markdown
## [Task Name] - Status Update
✅ Completed: [What's done]
🔄 In Progress: [Current work]
📋 Next Steps: [What's planned]
⚠️ Blockers: [Any issues]
```

### Issue Tracking
Deferred work goes in `artifacts/issues/TODO-YYYY-NNN_description.md`:
- Full context to resume work later
- Current state, desired state, and implementation notes
- References to related artifacts and code
- Status: Open → In Progress → Resolved/Cancelled

### Context Files
Permanent AI reference in `artifacts/context/`:
- Precise definitions tied to project edicts
- Implementation mappings to actual code
- Never deleted, always kept current
- Required files:
  - `api_contracts.md` - API specifications and contracts
  - `architecture.md` - System design decisions
  - `security.md` - Security requirements and decisions
  - `performance.md` - Performance budgets and constraints
  - `dependencies.md` - Library choices and rationale

Note: Not all projects require every context file. Create only those relevant to your project's needs.

### Checklists (NEW)
Complex tasks tracked in `artifacts/checklists/YYMMDD_HHMM_task.md`:
```markdown
# Checklist: [Task Name]
Started: YYYY-MM-DD HH:MM

## Steps
- [x] Step 1: Description
- [ ] Step 2: Description
- [ ] Step 3: Description

## Notes
[Discoveries and decisions during execution]

## Results
[Final outcome and any follow-up needed]
```

## Artifact Lifecycle

**Create** → **Develop** → **Validate** → **Promote** → **Clean**

1. **Create** with timestamp in appropriate subdirectory
2. **Develop** - Iterate and refine during development
3. **Validate** - Run tests and quality checks:
   ```bash
   # For code artifacts
   npm run lint -- artifacts/sketches/[file]
   npm test -- --testPathPattern=[file]
   ```
4. **Promote** to production when ready:
   - Documentation → Copy to `docs/`
   - Code → Integrate into `src/` with proper imports
   - Mark in devlog: `**PROMOTED**: [artifact] → [destination]`
5. **Clean** up stale artifacts periodically:
   - Run `/artifacts:status` to identify candidates
   - Archive valuable explorations
   - Delete truly temporary files

## Task Execution Patterns

### For Complex Tasks
<task>Execute complex multi-step task</task>
<approach>
1. Create checklist in artifacts/checklists/
2. Break down into atomic steps
3. Execute systematically
4. Update checklist after each step
5. Document discoveries in devlog
</approach>

### For Exploration
```markdown
/explore [concept]
# Creates: artifacts/sketches/YYMMDD_HHMM_explore_[concept].[ext]
# Updates: artifacts/devlog_YYMM.md with discoveries
# Outputs: Learning documentation + next steps
```

### For Analysis
```markdown
/sublime [target]
# Creates: artifacts/analyses/YYMMDD_HHMM_sublime_analysis.md
# Integration: Links to relevant context files
```

Note: These slash commands need to be created in `.claude/commands/`

Expected output format:
```markdown
# Analysis: [Target]
## Summary
- Health: X/10
- Critical Issues: N
- Quick Wins: N

## Critical Issues
[Detailed findings with file:line references]

## Recommendations
[Prioritized action items]

## Implementation Plan
[Step-by-step approach]
```

## Automation Integration

### Recommended Hooks
Example configuration in `.claude/settings.json` (customize for your needs):
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "path_pattern": "artifacts/sketches/.*\\.js$",
      "hooks": [{
        "type": "command",
        "command": "node --check ${FILE_PATH}"
      }]
    }]
  }
}
```

Example of parsing JSON stdin for hook scripts:
```bash
#!/bin/bash
# Example: parse-hook-input.sh
JSON=$(cat)
FILE_PATH=$(echo "$JSON" | jq -r '.filePath')
npm run lint -- "$FILE_PATH" || true
```

### Batch Processing
For repetitive artifact operations:
```bash
# Analyze all sketches
for sketch in artifacts/sketches/*.js; do
  claude -p "analyze $sketch for promotion readiness"
done

# Clean old artifacts
claude "/artifacts:cleanup --older-than 30d"
```

### Technical Notes
**Safe operations (sandbox=true):**
- Code analysis and review
- File inspection
- Git status checks
- Documentation generation

**Requires full access (sandbox=false):**
- Any write operations
- Network requests
- Build commands
- Test execution

## Context Management

### Context Preservation
Essential context stored in:
- `CLAUDE.md` - Project configuration
- `artifacts/context/` - Permanent references
- Recent devlog entries - Current work context


## Quality Gates

### Before Promotion
Artifacts must pass:
- [ ] Linting without errors
- [ ] Type checking (if applicable)
- [ ] Test coverage for new functionality
- [ ] Documentation of public APIs
- [ ] Review against project edicts

### Tracking Quality
Monthly quality metrics in devlog:
```markdown
## Month Summary - YYYY-MM
- Artifacts Created: N
- Promoted to Production: N
- Technical Debt Paid: N items
- Ship Mode Uses: N (target: <3)
```

## Integration with The Sublime

This workflow serves The Sublime by:
- **Encouraging experimentation** in isolated artifacts
- **Maintaining quality gates** at promotion boundaries
- **Preserving context** for long-term understanding
- **Tracking real progress** through honest devlog entries
- **Enabling continuous improvement** via issue tracking
- **Automating quality checks** through hooks

The artifacts directory is a laboratory where we experiment freely, fail safely, and promote only what achieves The Sublime.

For detailed commands and templates, see `.claude/commands/` for slash commands.