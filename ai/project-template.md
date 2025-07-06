# CLAUDE.md - [PROJECT_NAME]

## Project Overview
**Name**: [PROJECT_NAME]
**Purpose**: [What this project does]
**Tech Stack**: [Core technologies]
**Created**: YYYY-MM-DD

## Essential Commands

```bash
# Development
npm run dev              # Start dev server
npm run build            # Production build
npm run test             # Run test suite
npm run lint             # Lint code
npm run typecheck        # Type checking

# Validation (run before committing)
npm run lint && npm run typecheck && npm test

# Deployment
./scripts/deploy.sh staging
./scripts/deploy.sh production
```

## Code Style

**Naming Conventions**
- Components: PascalCase
- Functions/Variables: camelCase
- Constants: SCREAMING_SNAKE
- CSS: kebab-case

**Patterns**
- Prefer functional components with hooks
- TypeScript strict mode
- Early returns over nested conditionals
- Explicit error handling

**File Organization**
```
src/
├── components/      # Shared components
├── features/        # Feature modules
├── hooks/           # Custom hooks
├── utils/           # Utilities
├── services/        # External integrations
└── types/           # Type definitions
```

## Preferred Libraries
- State: Redux Toolkit
- Forms: React Hook Form
- Dates: date-fns
- HTTP: Axios
- Testing: Jest + React Testing Library
- Styling: [CSS Modules/Tailwind/styled-components]

## Project Edicts

### Edict.Compatibility.1
**Constraint**: [e.g., API v1 shape frozen]
**Reason**: [e.g., Mobile apps can't force update]
**Expires**: [Q3 2025]

### Edict.Performance.1
**Constraint**: [e.g., Page load < 2s on 3G]
**Reason**: [e.g., 40% users on slow networks]
**Expires**: [Review quarterly]

### Edict.Security.1
**Constraint**: [e.g., AES-256 encryption required]
**Reason**: [e.g., SOC2 compliance]
**Expires**: [Never - regulatory]

## Quality Metrics

### Current State
- Code coverage: [XX]%
- Bundle size: [X.X]MB
- Type coverage: [XX]%
- Performance score: [XX]/100

### Target State
- Code coverage: 80%+
- Bundle size: < 1MB
- Type coverage: 95%+
- Performance score: 90+/100

## Security Checklist
- [ ] No secrets in code
- [ ] Input validation on all user data
- [ ] Parameterized database queries
- [ ] Authentication on all endpoints
- [ ] Rate limiting implemented

## Notes
- Edicts expire - each has a removal plan
- Reference files in `artifacts/reference/` are source of truth
- Progress is measurable - track metrics monthly