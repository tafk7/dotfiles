# Test strategy

Local and CI tests use temporary HOME, XDG, PATH, and tmux roots. They must not
source the operator's startup files, write the default tmux server, install
packages, rotate real backups, or register plugins in a real CLI profile.

Run the local suite:

```bash
for test_file in tests/*.sh; do bash "$test_file"; done
python3 tests/startup-benchmark-test.py
python3 tests/theme-contrast.py
```

Run the base-versus-candidate startup regression check from an isolated copy of
the base revision:

```bash
python3 tests/startup-benchmark.py /path/to/base /path/to/candidate
```

The benchmark copies both revisions without live generated state and links the
actual startup files into isolated HOME directories. It starts with a clean
environment and deterministic direnv/Starship/uv/fzf/zoxide fixtures, then checks
that the intended profile, checkout, project exports, and interactive functions
loaded. A nonzero exit, startup diagnostic, or missing marker fails the run.
Interactive measurements use a controlling terminal; output is never silently
discarded. The fixture suppresses Ubuntu's first-shell sudo tutorial explicitly
and restricts Zsh's completion search to distribution-owned function directories,
so permissive host or runner plugin directories cannot trigger an interactive
`compinit` security prompt. It prepares a valid completion dump before sampling,
matching the documented warm-cache benchmark scope.

It takes at least 30 samples per revision for first environment initialization,
inherited environment, interactive startup (Bash and Zsh), and Bash export/function
snapshot replay. Base/candidate execution order alternates randomly; reports
include medians and p95. Use `--json /tmp/startup.json` to retain raw samples.
It fails when the candidate regression exceeds both 10 ms and 15%, and also
enforces a two-second catastrophic ceiling. These are warm-cache shell/config
measurements with controlled tools, not benchmarks of real tool releases,
Windows IPC, first prompt rendering, or model/tool transport latency.

`tests/project-environment.sh` requires direnv and tests actual authorized
project activation in fresh Bash/Zsh subprocesses, including a changed working
directory with inherited environment guards and rejection of an unapproved
`.envrc`. Bare Bash intentionally inherits its parent's environment. An agent
using snapshot replay must arrange activation separately when needed; a child
shell's activation does not update the agent parent's environment.

`tests/theme-refresh.sh` verifies the prompt fast path in both shells, including
global/session/window changes, standalone operation alongside a running tmux
server, enable/disable transitions, exit-status preservation, and fallback for
unfamiliar state. Unchanged prompts read freshness data with shell builtins and
make one tmux context query when inside tmux; they do not launch the full resolver.

## Platform confidence

- Native Ubuntu CI runs syntax, behavior, state, theme, installer, and config
  tests. The supported release matrix exercises Ubuntu 22.04, 24.04, and 26.04.
- The aarch64 jobs validate registry applicability and artifact-selection
  filters only. They are explicitly reported as `selection-only`; they do not
  claim ARM runtime execution.
- WSL2 behavior is mocked in normal CI, including the non-systemd shell fallback.
  A real Windows 11/WSL2 run remains periodic/manual because hosted Linux runners
  cannot validate Windows interop, the Windows agent pipe, or WSL lifecycle.
- xrdp has immutable dry-run and preflight unit coverage. Starting a real
  listener and validating an RDP desktop session is periodic/manual and requires
  Gate C approval on the target host.
- Work-host tests use mocked APT repositories, sudo, services, groups, Docker
  contexts, KVM, and `sbx`. They validate local-versus-remote Docker, pending
  login state, precise smoke cleanup, and forbidden broad/cloud operations.
  They do not execute a microVM or enroll a Tailscale node.
- The minimal-Ubuntu fixture verifies locale ordering, noninteractive APT, and
  bounded lock waiting. AI installer fixtures verify Codex prompt suppression
  and narrow Pi warning filtering without hiding unrelated npm diagnostics.

## Manual WSL2 checklist

1. Verify `wsl.exe --status` reports WSL2 and start a supported Ubuntu release.
2. Run `setup.sh --bash --dry-run`, then an approved real setup in a disposable
   WSL user profile.
3. With systemd enabled, verify `wsl2-ssh-agent.service` starts only when
   `~/.ssh/use-windows-agent` exists.
4. With systemd disabled, verify a new interactive shell uses the fallback and
   that a shell without the marker leaves `SSH_AUTH_SOCK` unchanged.
5. Confirm `bash -lc` and `zsh -lc` load Layer 0 only.

## Manual RDP checklist

After Gate C approval, run the requested `--rdp` setup on a disposable VM,
verify the selected port, TLS configuration, desktop session, and service state,
then run `bin/verify --tier rdp`. Confirm rollback from the timestamped xrdp
configuration backup before considering the live service test complete.

## Manual persistent work-host checklist

On an authorized disposable Ubuntu 24.04/26.04 VM or bare-metal host, expose
KVM/nested virtualization before setup. Run `setup.sh --full --tail`, log out
and reconnect after group changes, enroll Tailscale manually, authenticate
`sbx`, and run `bin/verify --tier work --tail --smoke`. Then validate a complete SSH
disconnect/reconnect and a reboot: `tailscaled` and Docker must return, group
access must stay active, and a new local sandbox must execute. This real-host
gate is required before claiming persistent work-host acceptance.
