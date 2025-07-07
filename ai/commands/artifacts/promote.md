---
description: Promote artifacts to production with full integration and verification
---

# Promote Artifact

Move artifact from temporary workspace to production location with full integration.

## Task

<task>Promote $ARGUMENTS to production</task>

<requirements>
1. Validate artifact is marked READY_ and has no TODOs
2. Determine correct production destination
3. Update all imports and references after move
4. Verify tests pass with new location
</requirements>

<phases>
1. **Validate** - Check readiness and destination
2. **Promote** - Move with reference updates
3. **Verify** - Confirm tests pass and log
</phases>

<output>
Terminal output (promotion summary with confirmation)
</output>

<error-handling>
File not found: List available READY_ files
No READY_ prefix: Explain workflow requirement
Target exists: Prompt for confirmation
</error-handling>

Promotion transforms experiments into production excellence. Quality gates protect integrity. Arete!