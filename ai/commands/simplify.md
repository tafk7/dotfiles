---
name: simplify
description: Analyze code for complexity and suggest simplifications
parameters:
  - name: target
    type: string
    required: false
    description: File or function to analyze (current file if not specified)
---

# Simplification Analysis{{#if target}} for {target}{{/if}}

Analyzing code complexity and identifying simplification opportunities...

## Complexity Metrics

Evaluating:
- Cyclomatic complexity
- Nesting depth
- Function length
- Parameter count
- Abstraction layers

## Simplification Targets

### 1. Structural Simplification
- Convert classes to functions where possible
- Flatten nested conditionals
- Eliminate unnecessary abstraction layers
- Merge similar functions
- Remove intermediate variables

### 2. Logic Simplification
- Replace complex conditionals with guard clauses
- Use early returns to reduce nesting
- Convert loops to comprehensions/functional style
- Eliminate state where possible
- Simplify boolean expressions

### 3. Data Simplification
- Use simpler data structures
- Eliminate unnecessary transformations
- Reduce the number of function parameters
- Remove redundant data copies
- Simplify type hierarchies

### 4. Dependency Simplification
- Remove unused imports
- Consolidate similar dependencies
- Replace complex libraries with simpler ones
- Use standard library when possible
- Eliminate circular dependencies

## Common Patterns to Simplify

### Before: Complex Class Hierarchy
```python
class AbstractProcessor:
    def process(self, data): pass

class ConcreteProcessor(AbstractProcessor):
    def process(self, data):
        return self._transform(data)

    def _transform(self, data):
        return data.upper()
```

### After: Simple Function
```python
def process(data: str) -> str:
    return data.upper()
```

### Before: Nested Conditionals
```python
def calculate_discount(user, product):
    if user.is_premium:
        if product.category == "electronics":
            if product.price > 100:
                return 0.2
            else:
                return 0.1
        else:
            return 0.05
    else:
        return 0
```

### After: Guard Clauses
```python
def calculate_discount(user, product):
    if not user.is_premium:
        return 0

    if product.category != "electronics":
        return 0.05

    return 0.2 if product.price > 100 else 0.1
```

## Simplification Checklist

- [ ] Can this be a function instead of a class?
- [ ] Can this be a module instead of a package?
- [ ] Can this be inline instead of abstracted?
- [ ] Can this use built-in types instead of custom ones?
- [ ] Can this be stateless instead of stateful?
- [ ] Can this be synchronous instead of async?
- [ ] Can this be a single file instead of multiple?
- [ ] Can this be declarative instead of imperative?

*Remember: The best code is simple code. Every abstraction must earn its complexity.*
