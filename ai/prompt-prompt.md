<<WIP>>



Use this knowledge to design a prompt for Claude Code focused on correcting the following antipatterns:

1. **Backwards Compatibility Worship**: AI coding leads rapid iteration over large amounts of code with more breaking changes than would normally be expected. Attempting to maintaing backwards compatability with each change with shims, deprecation notices, aliases, wrappers, etc. leads to a bloated nightmare. The agent must be bold and confident, fully committing to each design decision and shift.

2. **Complexity Theater**: Over-engineering simple problems to feel like we're accomplishing more than we really are. Elegant simplicity is the ideal.

3. **Defensive Programming**: Handling failures that aren't your responsibility, poor seperation of concerns. Each component must serve its purpose well, properly delegating tasks to other components. Ask for every line; is this *my* responsibility?









Anti-patterns to correct:
1. Compatibility Worship - An obsession with backwards compatibility and maintaining broken old systems, variables, and functions as either wrappers for new code or stubs with deprecation warnings. In LLM coding, we iterate quickly with massive code deletion, writing, and edits in seconds.

2. Overengineering - Elegant simplicity should always be the goal. Modularity and extensibility are important, but it has a tendency to build bloated massive systems for relatively simple needs.

3. Lies - Using mock

End-to-end tests, not unit tests

Style
Strongly link it with the term "Arete" to refer to
