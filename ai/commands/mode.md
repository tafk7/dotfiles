# Mode: {mode}

{{#if (eq mode "perfect")}}
## PERFECT MODE ACTIVATED

Code quality above all else. Zero technical debt tolerance.

**Priorities**: Best solution > Speed
**Constraints**: Ignored
**Refactoring**: Immediate
{{/if}}

{{#if (eq mode "ship")}}
## SHIP MODE ACTIVATED

Working solution within deadline. Document debt taken.

**Priorities**: Delivery > Perfection
**Constraints**: Primary concern
**Refactoring**: Deferred with TODO
{{/if}}

{{#if (eq mode "incremental")}}
## INCREMENTAL MODE ACTIVATED

Small, safe improvements toward perfection.

**Priorities**: Progress > Risk
**Constraints**: Respected
**Refactoring**: Opportunistic
{{/if}}
