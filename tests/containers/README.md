# Container scenarios

Scenarios that run dotfiles from a commit in throwaway Docker containers: a clean
Ubuntu, a real install, the real Claude Code and Codex CLIs. They need Docker, so
they are not part of the hermetic suite; `tests/testbed-frame.py` (in the suite)
checks the frame they run on without Docker.

```bash
python3 tests/containers/run.py --list
python3 tests/containers/run.py --out /tmp/testbed            # the quick scenarios, no network
python3 tests/containers/run.py --out /tmp/testbed --slow     # also the real installs (network)
python3 tests/containers/run.py --out /tmp/testbed --only dotfiles/agent-trust \
    --claude ~/.local/bin/claude --codex ~/.local/bin/codex
```

A run tests a commit (`--commit`, default `HEAD`), never uncommitted changes. It
writes `results.jsonl` (format in `lib/results.py`) and a log per scenario under
`logs/`, prints one line per scenario and a summary, and exits 0 only if every
scenario passed. There is no skip: a scenario that cannot run is an `error`.

## What a container may touch

`lib/container.py` starts every container and refuses, before Docker is called:
a writable mount; a mount whose source is not one of the run's declared inputs
(the commit's bundle, `lib/`, the agent binaries); an input that is `/`, the home
folder or a parent of it, or a socket; the host's network or PID namespace; and
any network for a scenario that did not declare one. Results leave by `docker
cp`. Containers run without capabilities unless a scenario needs `sudo`, with CPU,
memory and process limits. Everything a run creates carries the label
`testbed.run=RUN` and is removed at its end (`--keep-images` keeps the images).

## Agents without a model

Scenarios that start Claude Code or Codex mount the given binaries read-only and
point them at stand-in servers inside the container (`lib/fakes/`):
`messages.py` answers the Messages API, `responses.py` the Responses API. No
model is called and no credential is used; `ANTHROPIC_API_KEY=dummy`. The
Messages stand-in can also script a session: a request that offers tools gets
the next line of the session's script as a Bash tool call (see its docstring).

## Writing a scenario

A module in `scenarios/` with `NAME`, `SLOW`, `NETWORK`, `NEEDS`, `INTERFACE` and
`run(ctx)` (`lib/context.py`). Raise `lib.results.Failure` for a fail; anything
else raised is an error. Each scenario's docstring says its setup, what it checks
and what it covers.

The frame (`lib/`) is shared: other repositories' container scenarios use this
copy, at a pinned commit, through their own `run.py --plumbing DIR`. A change to
it is a change for them too.
