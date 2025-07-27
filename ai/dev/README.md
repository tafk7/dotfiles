# The Arete Framework

A philosophy-driven framework for AI-assisted development that pursues code in its highest form.

## Quick Start

```bash
# Analyze code quality
/arete

# Design a new system
/architect user authentication

# Ship a quick fix
/ship CRITICAL fix login bug

# Generate documentation
/scribe
```

## What is Arete?

Arete (ἀρετή) is ancient Greek for excellence, virtue, and the fulfillment of purpose. In this framework, it represents the pursuit of code that achieves its highest potential - where every line serves its purpose with crystalline clarity.

## Core Philosophy

The framework rests on three Prime Directives:

1. **Code Quality is Sacred** - Technical debt is heresy. Breaking changes that improve architecture are virtuous.
2. **Truth Over Comfort** - Reality trumps wishful thinking. Fake progress is worse than no progress.
3. **Simplicity is Divine** - Essential complexity only. Use what exists before creating what doesn't.

## Command Reference

The framework provides 20 slash commands organized by purpose:

### Analysis & Understanding
- `/arete` - Analyze code against Arete principles
- `/context` - Build deep understanding of codebase
- `/explain` - Deep analysis with educational focus
- `/profile` - Profile performance and generate optimizations
- `/edict` - Check compliance with project constraints

### Design & Architecture
- `/architect` - Design component structure and architecture
- `/refine` - Analyze and provide improvement checklist
- `/checklist` - Create actionable task lists

### Implementation
- `/implement` - Build features with proper architecture
- `/ship` - Fast delivery mode for deadlines
- `/explore` - Experimental sandbox without quality constraints
- `/hone` - Clean and optimize existing code

### Documentation
- `/scribe` - Generate permanent documentation with diagrams

### Git Operations
- `/git:commit` - Create smart commits with proper messages
- `/git:diff` - Analyze changes and implications

### Artifact Management
- `/_artifacts/status` - Display project health and activity
- `/_artifacts/todo` - Create tracked TODO issues
- `/_artifacts/promote` - Move artifacts to production
- `/_artifacts/cleanup` - Remove old artifacts
- `/_artifacts/log` - Append to development log

## Command Details

### Analysis Commands

#### `/arete`
Comprehensive analysis against Arete principles.
```
/arete                    # Current directory
/arete src/               # Specific directory
```

#### `/context`
Deep dive to establish mental model before implementation.
```
/context                  # Current directory
/context src/auth        # Specific component
```

#### `/explain`
Deep analysis with focus on understanding and education.
```
/explain                  # Current directory
/explain src/parser.py   # Specific file
```

### Design Commands

#### `/architect`
Design architecture for new components or systems.
```
/architect auth service   # Design authentication
/architect payment flow   # Design payment system
```

#### `/refine`
Analyze and create actionable improvement checklist.
```
/refine                   # Current directory
/refine src/api          # Specific component
```

### Implementation Commands

#### `/implement`
Implement with proper design and architecture.
```
/implement user profile page
/implement API rate limiting
```

#### `/ship`
Emergency mode for deadlines, creates debt tracking.
```
/ship fix login bug
/ship CRITICAL data issue
```

#### `/explore`
Sandbox mode with suspended quality rules.
```
/explore websocket patterns
/explore new UI framework
```

#### `/hone`
Find and remove dead code.
```
/hone                     # Current directory
/hone src/utils          # Specific directory
```

### Git Operations

#### `/git:commit`
Analyze changes and create meaningful commit messages.
```
/git:commit               # Commit all changes
/git:commit --amend      # Amend last commit
```

#### `/git:diff`
Analyze uncommitted changes and their implications.
```
/git:diff                 # All changes
/git:diff staged         # Staged only
```

### Artifact Management

#### `/_artifacts/status`
Display comprehensive artifact status and activity.
```
/_artifacts/status         # Full report
/_artifacts/status issues  # TODO items only
/_artifacts/status ready   # Promotion candidates
```

#### `/_artifacts/todo`
Create comprehensive TODO with context.
```
/_artifacts/todo refactor auth system
/_artifacts/todo BLOCKED fix circular dependency
```

#### `/_artifacts/promote`
Move artifacts to production directories.
```
/_artifacts/promote READY_design.md
/_artifacts/promote analyses/api_review.md
```

#### `/_artifacts/cleanup`
Remove old artifacts (30+ days).
```
/_artifacts/cleanup        # List candidates
/_artifacts/cleanup --execute  # Delete them
```

#### `/_artifacts/log`
Append progress to development log.
```
/_artifacts/log completed auth refactor
/_artifacts/log BLOCKED on payment gateway
```

## Setting Up

1. **Global Philosophy**: Place the Arete philosophy in `~/.claude/CLAUDE.md`
2. **Project Commands**: Commands live in `ai/commands/` directory
3. **Project Context**: Add project-specific guidance to `CLAUDE.md` in your project root

## Understanding Clara

Clara (Claude + Arete) is the AI persona who embodies this philosophy. When you invoke "Arete." you're calling Clara back to her highest purpose.

"Arete." serves as both invocation and reminder:
- When drifting toward over-engineering: "Arete."
- When tempted by fake progress: "Arete."
- When maintaining broken code: "Arete."

## The Quality Spectrum

Commands adapt to different needs:
- **Maximum Quality**: `/arete` for comprehensive analysis
- **Balanced**: `/refine` for pragmatic improvements
- **Speed Focus**: `/ship` when deadlines demand
- **No Constraints**: `/explore` for pure experimentation

## Key Principles

### For Users
- **Trust the AI** - Specify what, not how
- **Clear Goals** - State objectives, not implementations
- **Embrace Breaking Changes** - If they improve architecture
- **Delete Liberally** - Less code is better code

### For Contributors
- **Commands Serve Clear Purposes** - Each command has its place on the quality spectrum
- **Simplicity Over Features** - New commands must justify their existence
- **Real Examples Only** - Documentation uses actual commands
- **Format Consistency** - All commands follow the 3-tag format

## The Paradox

Perfect code that ships beats perfect code that doesn't. The framework embraces this tension, providing tools for both idealistic pursuit and pragmatic delivery.

## Learn More

- **Development Workflow**: See `workflow.md` for artifacts and development process
- **Best Practices**: See `BEST_PRACTICES.md` for usage patterns
- **Command Standards**: See `STANDARDS.md` for format specification
- **Creating Commands**: See `COMMAND_CREATION.md` for step-by-step guide

---

When in doubt, ask: "Does this serve Arete?"

When Clara strays, invoke: "Arete."