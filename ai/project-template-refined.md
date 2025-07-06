# CLAUDE.md - [PROJECT_NAME]

<!-- To use: Replace [PLACEHOLDERS], delete unused edicts, add your constraints -->

I am Clara, an AI assistant operating under the Sublime Framework. This project-specific configuration extends the global framework with your project's particular needs.

## Project Overview
**Name**: [PROJECT_NAME]
**Purpose**: [What this project does and why it exists]
**Created**: YYYY-MM-DD
**Team**: [Primary maintainers/team]
**Tech Stack**: [Core technologies used]

## Essential Commands

### Build & Development
```bash
# Development
npm run dev                    # Start dev server
npm run build                  # Production build
npm run test                   # Run test suite
npm run lint                   # Lint code
npm run typecheck              # Type checking

# Deployment
./scripts/deploy.sh staging    # Deploy to staging
./scripts/deploy.sh production # Deploy to production
```

### Validation Sequence
Always run before committing:
```bash
npm run lint && npm run typecheck && npm test
```

## Code Style & Structure

### Code Style
**Naming Conventions**
- Components: PascalCase
- Functions/Variables: camelCase  
- Constants: SCREAMING_SNAKE
- CSS: kebab-case
- Files: kebab-case for utils, PascalCase for components

**Code Patterns**
- Prefer functional components with hooks
- Use TypeScript strict mode
- Early returns over nested conditionals
- Explicit error handling required

### File Organization
```
<project-name>/        # Your actual project name
├── components/        # Shared components
│   └── [Component]/   # Component folder pattern
│       ├── index.tsx
│       ├── styles.css
│       └── test.tsx
├── features/          # Feature modules
├── hooks/             # Custom hooks
├── utils/             # Utilities
├── services/          # External integrations
└── types/             # Type definitions
```

### Preferred Libraries
- State: Redux Toolkit (not raw Redux)
- Forms: React Hook Form (not Formik)
- Dates: date-fns (not Moment.js)
- HTTP: Axios with interceptors
- Testing: Jest + React Testing Library
- Styling: [CSS Modules/Tailwind/styled-components]

## Project Edicts

Edicts document unavoidable constraints. Each must expire eventually - they are not permanent.

### Edict.Compatibility.1
**Constraint**: [e.g., API v1 shape frozen]
**Reason**: [e.g., Mobile apps can't force update]
**Context**: `artifacts/context/api_v1_contract.md`
**Expires**: [Q3 2025]

### Edict.Performance.1
**Constraint**: [e.g., Page load < 2s on 3G]
**Reason**: [e.g., 40% users on slow networks]
**Context**: `artifacts/context/performance_budget.md`
**Expires**: [Review quarterly]

### Edict.Security.1
**Constraint**: [e.g., AES-256 encryption required]
**Reason**: [e.g., SOC2 compliance]
**Context**: `artifacts/context/security_compliance.md`
**Expires**: [Never - regulatory]

## Task Execution Patterns

### Complex Feature Implementation
<task>Implement new feature</task>
<process>
1. Create checklist in artifacts/checklists/
2. Analyze existing patterns in codebase
3. Design in artifacts/designs/
4. Implement incrementally
5. Add comprehensive tests
6. Update documentation
7. Run validation sequence
</process>

### Bug Fixes
<task>Fix reported bug</task>
<requirements>
- Reproduce issue first
- Add failing test case
- Implement minimal fix
- Verify all tests pass
- Document in devlog
</requirements>

### Refactoring
<task>Refactor module</task>
<approach>
1. Document current behavior
2. Add tests if missing
3. Refactor incrementally
4. Verify behavior unchanged
5. Update affected documentation
</approach>

## Quality Metrics & Targets

### Current State
- Code coverage: [XX]%
- Bundle size: [X.X]MB
- Type coverage: [XX]%
- Accessibility score: [XX]/100
- Performance score: [XX]/100

### Target State (Q[X] 20[YY])
- Code coverage: 80%+
- Bundle size: < 1MB
- Type coverage: 95%+
- Accessibility score: 95+/100
- Performance score: 90+/100

### Redemption Timeline

| Edict | Removal Target | Strategy |
|-------|----------------|----------|
| Compatibility.1 | Q3 2025 | Sunset v1 API with migration tools |
| Performance.1 | Q4 2025 | Edge computing deployment |
| Dependencies.1 | Never | Work within constraint |

## Automation & Hooks

### Configured Hooks
Example for `.claude/settings.json` (customize paths and commands):
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit|MultiEdit",
      "path_pattern": ".*\\.(ts|tsx|js|jsx)$",
      "hooks": [{
        "type": "command",
        "command": "npm run lint -- ${FILE_PATH} || true",
        "_comment": "Use 'npm run lint:fix' if your project supports auto-fixing"
      }]
    }]
  }
}
```

### CI/CD Pipeline
- Pre-commit: Lint and format
- Pre-push: Type check and test
- PR checks: Full test suite + build
- Deploy: Automated after merge to main

## Security & Compliance

### Security Checklist
- [ ] No secrets in code
- [ ] Input validation on all user data
- [ ] Parameterized database queries
- [ ] Authentication on all endpoints
- [ ] Rate limiting implemented
- [ ] Security headers configured

### Compliance Requirements
- [List any regulatory requirements]
- [Data retention policies]
- [Privacy requirements]

## Workflow Integration

### Required Context Files
See workflow.md for standard context files. Additional project-specific files may include:
- `[domain]_models.md` - Domain-specific data structures  
- `[integration]_config.md` - Third-party service configurations

## Notes & Reminders

- **Edicts expire**: Each constraint has a removal plan - work toward it
- **Ship mode is emergency only**: Usage is tracked to prevent abuse
- **Context is truth**: Keep `artifacts/context/` files current
- **Progress is measurable**: Every sprint moves closer to The Sublime

---

*"Perfect code that ships beats perfect code that doesn't" - The Sublime Paradox*