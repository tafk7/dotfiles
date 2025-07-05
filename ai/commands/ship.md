---
descrption: Prioritize delivery over perfection - get it working and shipped
---

# Ship It Mode

Get $ARGUMENTS working now. Quality later. Document everything.

## Context
- Timestamp: !`date "+%Y-%m-%d %H:%M"`
- Mode: SHIP IT
- Ship count this month: !`grep -c "SHIP MODE:" artifacts/devlog_*.md 2>/dev/null || echo 0`

## Your Task

### Ship Mode Principles

**Working > Perfect** - If it runs, it ships.
**Today > Tomorrow** - Quick fixes now, elegance later.
**Progress > Polish** - User value first, code beauty second.

### Execute: $ARGUMENTS

**1. Make It Work**
- Fastest path wins
- Copy-paste OK
- Hard-code OK
- One test minimum
- Critical errors only

**2. Document Immediately**

Devlog entry + Redemption issue:
```markdown
## SHIP MODE: [Task] - YYYY-MM-DD HH:MM
Why: [Urgent reason]
Shortcuts: [What corners cut]
Cleanup: TODO-YYYY-NNN_[description].md
```

Issue must include:
- Each shortcut taken
- Steps to reach Sublime quality
- Clear acceptance criteria

### Ship Mode IS:
✓ Emergency escape hatch
✓ Documented compromise
✓ Temporary pragmatism

### Ship Mode IS NOT:
✗ Normal development
✗ License for broken code
✗ Permanent solution

> "Perfect code that ships beats perfect code that doesn't"
> - The Sublime Paradox

Every shortcut must be documented. Every compromise needs a restoration plan.

**Output**: Working code + documented shortcuts + redemption plan
