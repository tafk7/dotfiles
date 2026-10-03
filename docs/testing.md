# Testing

Tests use temporary HOME, XDG, PATH, and tmux roots. They must not source the
operator's startup files, use the default tmux server, install packages, rotate
real backups, or register plugins in a real CLI profile. Host-mutating commands
(APT, sudo, services, groups, Docker, KVM, `sbx`) are faked.

Run the suite (CI runs the same set, discovering every `tests/*.sh`):

```bash
for test_file in tests/*.sh; do bash "$test_file"; done
python3 tests/startup-benchmark-test.py
python3 tests/theme-contrast.py
python3 tests/documentation.py
python3 tests/eget-selection.py
python3 tests/ai-config.py
```

## Startup performance

Startup time matters because coding agents start a shell for every tool call.
Compare a candidate against an isolated copy of the base revision:

```bash
python3 tests/startup-benchmark.py /path/to/base /path/to/candidate
python3 tests/startup-benchmark.py /path/to/base /path/to/candidate --theme disabled
python3 tests/startup-benchmark.py /path/to/base /path/to/candidate --tools installed
```

The benchmark links each revision's startup files into isolated HOMEs and uses
deterministic direnv/Starship/uv/fzf/zoxide fixtures (`--tools installed` uses
the real local binaries instead). It covers first environment initialization,
inherited environment, interactive Bash and Zsh, and Bash snapshot replay. It
takes at least 30 samples per revision in random interleaved order and reports
median and p95; `--json FILE` keeps the raw samples. It fails when a regression
exceeds both 10 ms and 15%, or when any startup exceeds two seconds. A run also
fails if the expected profile, exports, or functions didn't load. These are
warm-cache shell measurements, not measurements of tool releases, Windows IPC,
or first-prompt rendering. Don't run them concurrently with other tests.

## Platform coverage

- **Ubuntu (CI):** the full suite plus syntax and shellcheck. A clean
  `ubuntu:24.04` container runs the real `--bash` installer as a non-root user,
  and 22.04, 24.04, and 26.04 containers each run the dry-run safety test.
- **aarch64:** registry checks on x86 runners report `selection-only`.
  `tests/eget-selection.py` replays eget's asset selection for every
  `eget.toml` entry on both architectures against recorded asset lists in
  `tests/fixtures/eget-assets/` (refresh with `--refresh` after bumping a tag),
  and checks that `eget.lock` records exactly those assets.
  `.github/workflows/arm64.yml` runs the real `--bash` installer on
  `ubuntu-24.04-arm` weekly and on installer changes. Dev/work tiers and APT
  repositories are not exercised on ARM.
- **WSL2:** mocked in CI, including the non-systemd fallback. Windows interop,
  the Windows agent pipe, and the WSL lifecycle need the manual checklist.
- **xrdp and work hosts:** dry-run, preflight, and mocked lifecycle coverage
  only. No test starts a real listener, executes a microVM, or enrolls
  Tailscale.

## Manual WSL2 checklist

1. Verify `wsl.exe --status` reports WSL2 and start a supported Ubuntu release.
2. Run `setup.sh --bash --dry-run`, then a real setup in a disposable WSL user.
3. With systemd enabled, verify `wsl2-ssh-agent.service` starts only when
   `~/.ssh/use-windows-agent` exists.
4. With systemd disabled, verify a new interactive shell uses the fallback and
   that a shell without the marker leaves `SSH_AUTH_SOCK` unchanged.
5. Confirm `bash -lc` and `zsh -lc` load Layer 0 only.

## Manual RDP checklist

On a disposable VM, run the `--rdp` setup, verify the port, TLS configuration,
desktop session, and service state, then run `bin/verify --tier rdp`. Confirm
you can restore from the timestamped xrdp configuration backup.

## Manual work-host checklist

On a disposable Ubuntu 24.04/26.04 VM or bare-metal host with KVM/nested
virtualization exposed, run `setup.sh --full --tail`, log out and back in,
enroll Tailscale, run `sbx login`, and run
`bin/verify --tier work --tail --smoke`. Then check that Docker, `tailscaled`,
group access, and a new local sandbox all survive an SSH reconnect and a reboot.
