# Test strategy

Local and CI tests use temporary HOME, XDG, PATH, and tmux roots. They must not
source the operator's startup files, write the default tmux server, install
packages, rotate real backups, or register plugins in a real CLI profile.

Run the local suite:

```bash
for test_file in tests/*.sh; do bash "$test_file"; done
python3 tests/theme-contrast.py
```

Run the base-versus-candidate startup regression check from an isolated copy of
the base revision:

```bash
python3 tests/startup-benchmark.py /path/to/base /path/to/candidate
```

The benchmark takes at least 30 samples for Bash and Zsh, for both Layer 0 and
interactive startup. It fails when the candidate regression exceeds both 10 ms
and 15%, and also enforces a two-second catastrophic ceiling.

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
