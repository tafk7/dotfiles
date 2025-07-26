# workflow.md - Development Process

This document defines a structured development workflow that separates experimental work from production code, ensuring clean version control and clear progression from ideas to implementation.

## Directory Structure

```
project/
├── artifacts/           # Temporary development work
│   ├── devlog_YYMM.md   # Monthly progress log
│   ├── issues/          # Deferred work with context
│   ├── analyses/        # Code analyses and explanations
│   ├── designs/         # Architecture proposals
│   ├── sketches/        # Quick experiments
│   ├── reference/       # Permanent AI references
│   └── checklists/      # Complex task tracking
├── src/                 # Production code
├── tests/               # Production tests
└── docs/                # Permanent documentation
```

## Core Concepts

### Temporal Artifacts
Everything in `artifacts/` is experimentation. Production code lives in `src/`, `tests/`, and `docs/`.

### Documentation Audiences
- **AI-optimized**: `reference/` and `checklists/` contain structured data for AI context
- **Human-readable**: Other artifacts use clear prose and visual diagrams (see ~/.claude/mermaid_reference.md)
- **Both**: Code and architecture diagrams serve all audiences effectively

### Naming Convention
Use semantic names that describe the content (e.g., `auth_refactor.md`, `user_api_design.md`).
Include timestamp at the top of the file content: `Created: YYYY-MM-DD HH:MM`

### Development Log
Track daily progress in `artifacts/devlog_YYMM.md`:
```markdown
## YYYY-MM-DD HH:MM  # Use: date "+%Y-%m-%d %H:%M"

**Task**: [Description]
**Impact**: [Quantify: lines reduced, performance gained, bugs fixed]
**Artifacts**: [Files created in artifacts/]
**Promoted**: [Files moved to production]
**Issues**: [Created: TODO-YYMM-NNN | Resolved: TODO-YYMM-NNN]

# Include timestamp at top of artifact files: Created: YYYY-MM-DD HH:MM

# Type additions: Bug(error,cause,fix), Feature(story,criteria), Refactor(metrics), Research(decisions)
# Milestones: === MILESTONE: [Achievement] === (>30% improvement)
```

### Issue Tracking
Deferred work in `artifacts/issues/TODO-YYMM-NNN_description.md`:
- Full context to resume later
- Current state, desired state, implementation notes
- Status: Open → In Progress → Resolved

### Reference Files
Permanent references in `artifacts/reference/`:
- `architecture.md` - System design decisions
- `api_contracts.md` - API specifications
- `security.md` - Security requirements
- `performance.md` - Performance constraints
- `dependencies.md` - External dependencies and rationale

## Task Execution Patterns

<task>Complex Feature Implementation</task>
<process>
1. Create checklist in artifacts/checklists/
2. Analyze existing patterns
3. Design in artifacts/designs/
4. Implement incrementally
5. Add comprehensive tests
6. Update documentation
7. Run validation sequence
</process>

<task>Bug Fix</task>
<requirements>
- Reproduce issue first
- Add failing test
- Implement minimal fix
- Verify all tests pass
- Log in devlog
</requirements>

<task>Refactoring</task>
<approach>
1. Document current behavior
2. Add tests if missing
3. Refactor incrementally
4. Verify behavior unchanged
5. Update documentation
</approach>

<task>Code Analysis</task>
<focus>
- Arete alignment check
- Deletion opportunities
- Complexity reduction
- Pattern violations
</focus>

## Artifact Lifecycle

1. **Create** with timestamp in appropriate subdirectory
2. **Develop** iteratively within artifacts/
3. **Validate** against quality gates
4. **Promote** to production when ready
5. **Clean** stale artifacts periodically

## Quality Gates

Before promoting artifacts:
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Tests cover new functionality
- [ ] Documentation updated
- [ ] Aligns with project edicts

## Progress Tracking

Update format for complex tasks:
```markdown
## [Task Name] - Status Update
✅ Completed: [What's done]
🔄 In Progress: [Current work]
📋 Next Steps: [What's planned]
⚠️ Blockers: [Any issues]
```

## Monthly Summary
Track in devlog:
- Artifacts created
- Promoted to production
- Technical debt paid
- Quality metrics improved
