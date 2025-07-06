# workflow.md - Development Process

This document defines the development workflow. For philosophy, see global CLAUDE.md. For project specifics, see your project's CLAUDE.md.

## Directory Structure

```
project/
├── artifacts/           # Temporary development work
│   ├── devlog_YYMM.md   # Monthly progress log
│   ├── issues/          # Deferred work with context
│   ├── analyses/        # Code quality analyses
│   ├── designs/         # Architecture proposals
│   ├── sketches/        # Quick experiments
│   ├── context/         # Permanent AI references
│   └── checklists/      # Complex task tracking
├── src/                 # Production code
├── tests/               # Production tests
└── docs/                # Permanent documentation
```

## Core Concepts

### Temporal Artifacts
Everything in `artifacts/` is experimentation. Production code lives in `src/`, `tests/`, and `docs/`.

### Naming Convention
`YYMMDD_HHMM_description.ext` (e.g., `241215_1430_auth_refactor.md`)

### Development Log
Track daily progress in `artifacts/devlog_YYMM.md`:
```markdown
## YYYY-MM-DD HH:MM - [Task]: [Description]
**Impact**: [What changed]
**Artifacts**: [Files created/modified]
**Next**: [Follow-up actions]
```

### Issue Tracking
Deferred work in `artifacts/issues/TODO-YYMM-NNN_description.md`:
- Full context to resume later
- Current state, desired state, implementation notes
- Status: Open → In Progress → Resolved

### Context Files
Permanent references in `artifacts/context/`:
- `architecture.md` - System design decisions
- `api_contracts.md` - API specifications
- `security.md` - Security requirements
- `performance.md` - Performance constraints
- `dependencies.md` - Library choices

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
- Sublime alignment check
- Deletion opportunities
- Library replacement candidates
- Complexity reduction
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
