---
name: thread-handoff
description: "Create a portable semantic handoff from an active or saved Codex thread when moving to another model, provider, deployment, or session. Use it before a planned switch or to recover useful context from a thread that can no longer continue."
---

# Thread Handoff

Create a concise, evidence-based checkpoint that another Codex thread can use without depending on provider-side conversation objects, response IDs, or encrypted reasoning items.

## Choose the source

- For the active thread, synthesize the handoff from the conversation and current workspace state.
- For a saved or broken thread ID, run `python3 scripts/extract_thread.py <thread-id>` to recover its visible user and assistant messages. Increase `--last-messages` only when earlier context is necessary.
- Inspect the current repository state and relevant files when the handoff concerns code or artifacts. Treat the transcript as intent/history, not proof that a change still exists.

## Produce the handoff

Include only sections that carry useful state:

1. **Objective** — the user's actual goal and definition of done.
2. **Current state** — what is complete, in progress, or blocked.
3. **Decisions and rationale** — durable choices the next thread should preserve.
4. **Workspace evidence** — relevant files, branches, commits, commands, and validation results.
5. **Open questions and risks** — unresolved facts and assumptions, clearly labeled.
6. **Next action** — the first concrete step for the receiving thread.
7. **Resume prompt** — a self-contained prompt the user can paste into a fresh thread.

Prefer a compact handoff over a chronological transcript. Preserve exact identifiers, paths, errors, and commands only when they matter to continuation.

## Portability constraints

- Do not include hidden chain-of-thought. Record decisions, evidence, and concise reasoning conclusions.
- Do not copy secrets, credentials, authorization headers, or raw environment dumps.
- For cross-provider or cross-deployment handoffs, omit response IDs, item IDs, `previous_response_id`, encrypted reasoning payloads, and other provider-bound state. Describe their implications in plain text when relevant.
- Do not imply that a textual handoff transfers server-side conversation state. It creates a new conversation with equivalent working context.
- Distinguish verified repository state from claims found only in prior messages.
- Do not claim tests or commands succeeded unless the transcript or current workspace provides evidence.

## Saving the result

Return the handoff in the response unless the user requests a file or a durable workspace artifact is clearly useful. When saving, prefer `.agents/handoffs/<timestamp>-<slug>.md` in the active project and report the path.

When deployment affinity caused the handoff, record the source model, provider, and deployment if known, plus the destination selection. A thread containing Azure Responses API items must continue on the resource that created them; otherwise start a new thread from the text handoff.
