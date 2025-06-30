# Mermaid Quick Reference

## Critical Rules
1. **Start with diagram type**: `flowchart TD`, `sequenceDiagram`, `classDiagram`, etc.
2. **"end" keyword**: Use `End`, `(end)`, or `"end"` - never lowercase `end`
3. **"o"/"x" first letters**: Use `A--- oB` not `A---oB` (creates circle edge)
4. **Quote complex text**: `A["Text with % or (symbols)"]`
5. **Comments**: `%% Comment text` on separate lines

## Common Syntax Errors
- **Wrong arrows**: `A->B` ❌ → `A-->B` ✅
- **Reserved words**: `A[end]` ❌ → `A[End]` ✅
- **Unquoted special chars**: `A[100%]` ❌ → `A["100%"]` ✅
- **Missing diagram type**: Always start with declaration

## Quick Syntax

### Flowcharts
```
flowchart TD
A[Rectangle] --> B(Round)
C{Diamond} --> D((Circle))
E["Quoted text with %"]
```

### Sequence Diagrams
```
sequenceDiagram
participant A as Alice
A->>B: Message
B-->>A: Dotted response
Note right of A: Note text
```

### Class Diagrams
```
classDiagram
class User {
  +String name
  +login()
}
User --> Role
```

## Character Escaping
- **Special chars**: Use quotes `A["Text with % & symbols"]`
- **Entity codes**: `#35;` for #, `#9829;` for ♥
- **Semicolon**: Use `#59;` in sequence diagram text
- **Commas in styles**: Escape as `\,`

## Troubleshooting Checklist
1. ✅ Diagram type declared?
2. ✅ No lowercase "end"?
3. ✅ Complex text quoted?
4. ✅ Double dashes in arrows?
5. ✅ Balanced brackets?

**Remember**: Syntax errors break diagrams, typos break diagrams, parameters fail silently.
