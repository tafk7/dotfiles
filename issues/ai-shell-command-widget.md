# Inline conversational AI shell-command generator

**Status:** proposed.

## User motivation and use case

The user misses VS Code's inline AI command-generation workflow. While sitting
at a shell prompt, they want to type a natural-language description such as:

```text
find every JSON file changed in the last week
```

Then they want to press a shortcut and have the editable shell buffer replaced
with the proposed command:

```bash
find . -type f -name '*.json' -mtime -7
```

The command must not execute automatically. The user should be able to inspect
and edit it normally before pressing Enter.

The important improvement over a one-shot AI prompt is conversational
correction. Pressing the shortcut again should let the user provide feedback
such as:

```text
use absolute paths and exclude node_modules
```

The tool should continue the same dedicated AI conversation and replace the
buffer with a corrected command. This should feel like a lightweight,
shell-native equivalent of an inline IDE prompt, optimized for forgotten Linux
commands, command composition, and quick scripts.

The user works both inside and outside tmux. The initial placeholder keybinding
should be `Alt+I`, which is currently unbound by tmux and works as a normal Meta
key in Bash Readline and Zsh ZLE. `Alt+Shift+I` may be used to reset the current
command-generation conversation.

## Implementation prompt

Implement an inline, conversational AI shell-command generator for this
dotfiles repository.

### Repository context

Inspect the repository and follow its existing architecture and conventions
before editing.

Relevant details already identified:

- Both Bash and Zsh are supported.
- `shell/init.sh` automatically sources every `shell/tools/*.sh` module.
- Existing AI integrations are in:
  - `shell/tools/claude.sh`
  - `shell/tools/codex.sh`
  - `shell/tools/opencode.sh`
  - `shell/tools/pi.sh`
- The installed Claude CLI supports noninteractive output, explicit session
  IDs, exact-session resume, structured output, safe mode, and disabling tools.
- The installed Codex CLI supports `codex exec`, JSON event output, and
  `codex exec resume <session-id>`.
- Pi supports explicit session IDs, noninteractive output, and `--no-tools`.
- FZF is already part of the environment.
- Tmux has no `M-i` or `M-I` binding, so those keys pass through to the shell.
- Do not alter or break the existing Claude, Codex, opencode, or Pi aliases.
- Preserve the repository's Bash/Zsh portability and re-source safety
  conventions.

### Desired user experience

Initial request:

```text
$ find every JSON file changed in the last week
                                      [Alt+I]
```

The buffer becomes:

```text
$ find . -type f -name '*.json' -mtime -7
```

Pressing `Alt+I` again should solicit corrective feedback without losing the
current candidate:

```text
refine> use absolute paths and exclude node_modules
```

The buffer then becomes something like:

```bash
find "$PWD" -path '*/node_modules' -prune -o \
    -type f -name '*.json' -mtime -7 -print
```

The exact UI may differ, but preserve these semantics:

1. The initial natural-language request may be typed directly into the shell
   buffer.
2. `Alt+I` transforms it into a command.
3. The generated command is inserted into the editable buffer and never
   automatically executed.
4. `Alt+I` on an active generated result prompts for corrective feedback.
5. The previous suggestion, any user edits to it, and the feedback are supplied
   to the same AI conversation.
6. `Alt+Shift+I` resets the dedicated conversation.
7. Cancellation or backend failure leaves the existing buffer intact.
8. Once the user executes a command or returns to a fresh prompt, the next
   `Alt+I` request should normally start a new command conversation.
9. Changing working directories must not silently reuse stale directory
   context. Prefer starting a new conversation when `$PWD` changes.
10. The behavior must work identically inside and outside tmux.

### Implementation architecture

Prefer a small, maintainable separation between:

1. Shell integration:
   - Bash Readline widget.
   - Zsh ZLE widget.
   - Per-shell state.
   - Buffer capture and replacement.
   - Refinement input UI.
   - Keybindings.
2. Backend command:
   - Invokes the selected AI harness.
   - Creates or resumes an exact session.
   - Supplies a narrowly scoped system prompt.
   - Produces a clean command string on stdout.
   - Sends diagnostics and errors to stderr.
   - Never executes the generated command.

A likely layout is:

```text
shell/tools/ai-command.sh
bin/ai-command
```

Adjust this if existing repository conventions suggest a better arrangement.

Keep conversational state isolated per interactive shell or pane. Do not use
broad options such as Claude's `--continue`, Codex's `--last`, or opencode's
generic continue-last behavior. Those could accidentally resume an unrelated
coding-agent conversation.

The shell integration can own state such as:

```text
_AI_COMMAND_SESSION_ID
_AI_COMMAND_LAST_RESULT
_AI_COMMAND_CWD
_AI_COMMAND_ACTIVE
```

Avoid a shared global session that could mix prompts from multiple shells or
tmux panes.

### Backend requirements

Implement Claude as the initial backend, but structure the interface so Codex
or Pi adapters can be added later without changing the shell widget.

Use a dedicated explicit UUID for each command-generation conversation:

- Initial request: create the Claude conversation using that UUID.
- Refinement: resume that exact UUID.
- Reset or new request: generate a new UUID.

Verify the exact supported syntax against the installed Claude version rather
than assuming it.

Run Claude with the safest practical configuration:

- Noninteractive/print mode.
- Safe mode if compatible with the required authentication.
- No tools.
- No shell execution.
- No project instructions, plugins, hooks, MCP servers, or unrelated
  coding-agent customization if those can be disabled safely.
- Structured output if supported reliably.
- A narrowly scoped system prompt.
- An optional fast-model override suitable for short shell-command generation.

The system prompt should communicate approximately:

- Act only as a shell-command drafting assistant.
- Target the user's actual shell and Linux environment.
- Return a command or short shell script only.
- Do not use Markdown fences.
- Do not explain the command unless explicitly requested.
- Never execute anything.
- Respect the current working directory.
- Preserve the intent of previous suggestions when processing corrections.
- Prefer clear and safe commands.
- Quote paths and variables correctly.
- Do not invent utilities unnecessarily.
- It is acceptable to return a multiline shell construct when the task
  genuinely requires one.

Provide the backend with only useful context:

- Shell type.
- Current working directory.
- Initial request or corrective feedback.
- Current command candidate during refinement.
- Possibly basic OS information.

Do not send shell history, secrets, or the full environment.

### Configuration

Support at least:

```bash
AI_COMMAND_BACKEND=claude
AI_COMMAND_MODEL=<optional model override>
```

The default should work with the user's existing Claude authentication.

Do not blindly reuse arbitrary `CLAUDE_FLAGS`, since those flags may enable
tools, project settings, a different permission mode, or other behavior
unsuitable for this restricted helper. If existing flags are reused at all, do
so deliberately and document the implications.

### Shell behavior

For Bash:

- Use a Readline widget with `bind -x`.
- Read and update `READLINE_LINE`.
- Place `READLINE_POINT` at the end of the generated command.
- Bind `Alt+I` without affecting Tab completion.
- Bind `Alt+Shift+I` to reset state.

For Zsh:

- Use a ZLE widget.
- Read and update `BUFFER`.
- Position the cursor at the end.
- Redisplay cleanly while waiting for the backend.
- Bind `Alt+I` and `Alt+Shift+I`.

Only install interactive bindings in interactive shells. Preserve the
repository's noninteractive and agent-shell startup guarantees.

The refinement prompt may use FZF because it is already installed. A simple
`fzf --phony --print-query`-style input dialog is acceptable. Provide a
reasonable fallback or a clear error if FZF is unexpectedly unavailable. Do
not introduce a large new UI dependency solely for this prompt.

While inference is running, show a small non-destructive status indicator if
practical. Avoid corrupting the prompt or leaving terminal escape sequences
behind.

Never evaluate generated output. Treat it purely as text assigned to the shell
buffer.

### Error handling

Handle at least:

- Empty initial request.
- Empty or cancelled refinement.
- Missing backend executable.
- Authentication failure.
- Backend timeout or nonzero exit.
- Malformed structured output.
- Empty command result.
- Interrupted request with `Ctrl+C`.
- Working-directory change.
- Re-sourcing shell configuration.
- Generated multiline commands.
- Multiple simultaneous shell or tmux sessions.

On failure:

- Preserve or restore the original buffer.
- Print a concise error.
- Return control to the prompt cleanly.
- Do not leave the state marked as an active successful suggestion.

### Testing

Add focused automated tests consistent with the repository's existing shell
test harness.

Use a stub Claude executable rather than making live model calls. Test:

- Initial request creates an explicit session.
- Refinement resumes the same exact session.
- Reset creates a new session.
- A new working directory does not reuse stale context.
- Generated output replaces the buffer but is not executed.
- User-edited candidate text is included in refinement context.
- Cancellation preserves the buffer.
- Backend failure preserves the buffer.
- Malformed and empty backend output are rejected.
- Multiline command output survives correctly.
- Bash and Zsh bindings are installed only interactively.
- Re-sourcing does not duplicate hooks or corrupt state.
- Existing AI aliases continue to behave as before.
- `Alt+I` does not collide with the tracked tmux configuration.

Run the relevant existing tests in addition to the new tests.

### Documentation

Update the README or appropriate customization documentation with:

- The motivation and intended workflow.
- The `Alt+I` generate/refine binding.
- The `Alt+Shift+I` reset binding.
- Examples of initial generation and corrective feedback.
- The fact that generated commands are inserted but never executed.
- Supported shells.
- Behavior inside and outside tmux.
- Backend and model configuration.
- Security and privacy behavior.
- How to disable or remap the bindings.

### Implementation constraints

- Follow the repository's existing style.
- Keep the implementation focused and reasonably small.
- Do not add an external AI CLI when existing harnesses can provide the
  functionality.
- Do not auto-execute generated commands.
- Do not resume unrelated AI sessions.
- Do not overwrite unrelated user configuration.
- Preserve existing uncommitted changes.
- Use `apply_patch` for edits.
- Validate behavior in both Bash and Zsh.
- At completion, summarize the files changed, the resulting UX, test results,
  and any remaining limitations.
