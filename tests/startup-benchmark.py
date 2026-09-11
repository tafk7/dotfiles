#!/usr/bin/env python3
"""Compare real startup chains in isolated, validated shell/tool fixtures."""
from __future__ import annotations

import argparse
import contextlib
import errno
import fcntl
import json
import os
import pathlib
import pty
import random
import select
import shutil
import signal
import statistics
import subprocess
import tempfile
import termios
import time

RUNS = max(30, int(os.environ.get("DOTFILES_BENCH_RUNS", "30")))
MARKER = b"DOTFILES_BENCH_OK"


def distribution_zsh_fpath() -> str:
    """Return deterministic distro-owned Zsh function directories."""
    proc = subprocess.run(
        ["/usr/bin/zsh", "-dfc", "print -rl -- $fpath"],
        env={"HOME": "/nonexistent", "PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"},
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    roots = [
        entry for entry in proc.stdout.splitlines()
        if entry.startswith(("/usr/share/zsh/", "/usr/lib/zsh/")) and pathlib.Path(entry).is_dir()
    ]
    if not any((pathlib.Path(entry) / "compinit").is_file() for entry in roots):
        raise RuntimeError("Unable to locate compinit in the distribution Zsh function path")
    return ":".join(roots)


def execute(argv: list[str], env: dict[str, str], cwd: pathlib.Path, interactive: bool = False) -> tuple[float, bytes]:
    """Use a controlling terminal for interactive shells; retain diagnostics."""
    start = time.perf_counter_ns()
    if not interactive:
        proc = subprocess.run(argv, env=env, cwd=cwd, capture_output=True, timeout=10)
        output = proc.stdout
        if proc.returncode or proc.stderr:
            raise RuntimeError(f"Startup failed: {argv[0]} (exit {proc.returncode})\n{proc.stderr.decode(errors='replace')}")
    else:
        master, slave = pty.openpty()

        def terminal_session() -> None:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        try:
            proc = subprocess.Popen(argv, env=env, cwd=cwd, stdin=slave, stdout=slave,
                                    stderr=slave, preexec_fn=terminal_session)
        finally:
            os.close(slave)
        chunks = []
        try:
            deadline = time.monotonic() + 10
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not select.select([master], [], [], remaining)[0]:
                    captured = b"".join(chunks).decode(errors="replace")
                    raise TimeoutError(
                        f"Interactive startup exceeded 10 seconds: {argv[0]}\n"
                        f"Captured terminal output:\n{captured}"
                    )
                try:
                    chunk = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
                chunks.append(chunk)
            if proc.wait(timeout=1):
                raise RuntimeError(f"Interactive startup failed: {b''.join(chunks)!r}")
            output = b"".join(chunks)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            os.close(master)
    return (time.perf_counter_ns() - start) / 1e6, output


class Fixture:
    """Copy code, never the operator's generated state, profiles or environment."""

    def __init__(self, source: pathlib.Path):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-benchmark-")
        self.root = pathlib.Path(self.temp.name)
        self.tree = self.root / "checkout"
        shutil.copytree(source, self.tree, ignore=shutil.ignore_patterns(
            ".git", "generated", ".backups", "__pycache__"))
        self.env = {
            "HOME": str(self.root / "home"), "PATH": f"{self.root}/bin:/usr/bin:/bin",
            "LANG": "C.UTF-8", "TERM": "xterm-256color", "USER": "fixture",
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "TMPDIR": str(self.root / "tmp"), "TMUX_TMPDIR": str(self.root / "tmux"),
            "TMUX": "", "DOTFILES_DIR": str(self.tree), "WIN_USER": "fixture",
            "DOTFILES_BENCH_TREE": str(self.tree),
            "DOTFILES_LEGACY_GENERATED_DIR": str(self.root / "legacy"),
            # Hosted runners commonly expose writable /usr/local completion
            # directories. A real TTY makes compinit prompt about those paths,
            # turning a startup benchmark into an input wait. Benchmark only
            # the distro-owned completion tree; user/plugin completion paths
            # are represented by the controlled fixture cache below.
            "FPATH": distribution_zsh_fpath(),
        }
        for name in ("home", "bin", "config", "data", "state", "cache", "tmp", "tmux", "legacy"):
            (self.root / name).mkdir()
        # Suppress Ubuntu's first-shell sudo tutorial in this disposable HOME.
        (self.root / "home/.sudo_as_admin_successful").touch()
        for source_name, target in {
            "profile.sh": ".profile", "bash.sh": ".bashrc", "bash_profile": ".bash_profile",
            "zshenv": ".zshenv", "zsh.sh": ".zshrc", "zprofile": ".zprofile",
        }.items():
            (self.root / "home" / target).symlink_to(self.tree / "entry" / source_name)
        # Stable tool-presence/initialization fixtures. These exercise adapters,
        # not the performance of real uv/fzf/Starship releases or Windows IPC.
        scripts = {
            "direnv": 'if [[ "$1" == export ]]; then printf "export DOTFILES_BENCH_PROJECT=%q\\n" "$PWD"; else echo :; fi',
            "uv": 'if [[ "${2:-}" == zsh ]]; then printf "#compdef uv\\n_uv() { :; }\\n"; else echo :; fi',
            "starship": 'echo :', "fzf": 'echo :', "zoxide": 'echo :',
        }
        for name, body in scripts.items():
            p = self.root / "bin" / name
            p.write_text("#!/bin/bash\n" + body + "\n")
            p.chmod(0o755)
        self.inherited: dict[str, dict[str, str]] = {}
        for shell in ("bash", "zsh"):
            argv = self.command(shell, "first-env", 'command env -0')
            _, raw = execute(argv, self.env, self.tree)
            self.inherited[shell] = dict(item.decode().split("=", 1) for item in raw.split(b"\0") if item)
        self.snapshot = self.root / "snapshot.sh"
        capture = 'benchmark_snapshot_probe() { :; }; export -p; declare -f'
        _, raw = execute(self.command("bash", "first-env", capture), self.env, self.tree)
        self.snapshot.write_bytes(raw)

    def close(self) -> None:
        self.temp.cleanup()

    def command(self, shell: str, mode: str, body: str) -> list[str]:
        if mode == "snapshot":
            return ["/bin/bash", "--noprofile", "--norc", "-c", 'source "$1" || exit; ' + body, "benchmark", str(self.snapshot)]
        if mode == "interactive":
            return ["/bin/bash", "-ic", body] if shell == "bash" else ["/usr/bin/zsh", "-dic", body]
        # Bash -c deliberately reads no user startup files. Exercise the real
        # login chain; Zsh nonlogin reads .zshenv without an interactive profile.
        return ["/bin/bash", "-lc", body] if shell == "bash" else ["/usr/bin/zsh", "-dc", body]

    def sample(self, shell: str, mode: str) -> float:
        checks = [
            '[[ "$DOTFILES_DIR" == "$DOTFILES_BENCH_TREE" ]] || exit 81',
            '[[ "${_DOTFILES_ENV_LOADED:-}" == 1 ]] || exit 82',
            '[[ "${DOTFILES_BENCH_PROJECT:-}" == "$PWD" ]] || exit 83',
        ]
        if mode == "snapshot":
            checks.append('typeset -f benchmark_snapshot_probe >/dev/null || exit 84')
        else:
            checks.append('[[ "${_PROFILE_LOADED:-}" == 1 ]] || exit 85')
        if mode == "interactive":
            checks += ['typeset -f reload >/dev/null || exit 86',
                       '[[ -n "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" ]] || exit 87',
                       'unset HISTFILE']
        checks.append('printf "DOTFILES_BENCH_OK\\n"')
        env = self.env if mode == "first-env" else self.inherited[shell]
        elapsed, output = execute(self.command(shell, mode, "; ".join(checks)), env, self.tree, mode == "interactive")
        if output.strip() != MARKER:
            raise RuntimeError(f"Unexpected startup output ({shell}/{mode}): {output!r}")
        return elapsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("--json", type=pathlib.Path, help="Save sample distributions and summaries")
    args = parser.parse_args()
    failed = False
    results = {}
    rng = random.Random(20260911)
    with contextlib.ExitStack() as stack:
        fixtures = [Fixture(path.resolve()) for path in (args.baseline, args.candidate)]
        for fixture in fixtures:
            stack.callback(fixture.close)
        cases = [(shell, mode) for shell in ("bash", "zsh") for mode in ("first-env", "inherited", "interactive")]
        cases.append(("bash", "snapshot"))
        for shell, mode in cases:
            samples: list[list[float]] = [[], []]
            for i in range(RUNS + 3):
                order = [0, 1]
                rng.shuffle(order)
                for index in order:
                    elapsed = fixtures[index].sample(shell, mode)
                    if i >= 3:
                        samples[index].append(elapsed)
            old, new = [statistics.median(s) for s in samples]
            delta = new - old
            percent = delta / old * 100
            p95 = [sorted(s)[int(.95 * (len(s) - 1))] for s in samples]
            print(f"{shell:4} {mode:11} median {old:7.2f} -> {new:7.2f} ms; p95 {p95[0]:7.2f} -> {p95[1]:7.2f} ms; {percent:+.1f}%", flush=True)
            results[f"{shell}/{mode}"] = {"baseline_ms": samples[0], "candidate_ms": samples[1], "baseline_median_ms": old, "candidate_median_ms": new}
            if new > 2000 or (delta > 10 and percent > 15):
                failed = True
    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
