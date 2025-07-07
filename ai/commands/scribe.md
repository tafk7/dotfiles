---
description: Generate permanent project documentation in docs/
---

# Scribe

Analyze $ARGUMENTS deeply, then generate focused documentation (1-5 files) appropriate to what you discover.

## Task

<task>Analyze $ARGUMENTS and create permanent documentation that captures what matters most</task>

<requirements>
1. Maximum 5 documentation files per analysis
2. Prioritize clarity and visual understanding
3. Include diagrams where they clarify concepts (see ~/.claude/mermaid_reference.md)
4. Focus on the "why" before the "how"
</requirements>

<phases>
1. **Discovery** - Map structure and assess scope
2. **Deep Dive** - Analyze patterns, purpose, and design
3. **Synthesis** - Plan documentation structure
4. **Generate** - Create focused docs with visuals
</phases>

<output>
docs/ directory (permanent documentation)
</output>

<conditional>
If small project: Single comprehensive README
If complex system: Multiple focused files
If existing docs: Update and enhance
</conditional>

<error-handling>
No source files: Document available structure
Target unclear: Ask for specific focus area
</error-handling>

# Arguments: $ARGUMENTS accepts:
# - Directory path: Analyze entire codebase
# - Specific topic: Focus documentation on that area
# - --update: Refresh existing documentation

The best documentation teaches visually what words alone cannot convey.