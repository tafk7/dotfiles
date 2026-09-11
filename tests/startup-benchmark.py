#!/usr/bin/env python3
"""Compare shell startup medians for a baseline and candidate checkout."""

from __future__ import annotations

import os
import pathlib
import statistics
import subprocess
import sys
import tempfile
import time


RUNS = int(os.environ.get("DOTFILES_BENCH_RUNS", "30"))


def measure(tree: pathlib.Path, shell: str, interactive: bool) -> float:
    with tempfile.TemporaryDirectory(prefix="dotfiles-bench-") as tmp:
        root = pathlib.Path(tmp)
        env = os.environ.copy()
        env.update(
            HOME=str(root / "home"),
            XDG_CONFIG_HOME=str(root / "config"),
            XDG_DATA_HOME=str(root / "data"),
            XDG_STATE_HOME=str(root / "state"),
            XDG_CACHE_HOME=str(root / "cache"),
            DOTFILES_GENERATED_DIR=str(root / "cache" / "theme"),
            DOTFILES_DIR=str(tree),
            TMUX="",
        )
        for value in env.values():
            if isinstance(value, str) and value.startswith(str(root)):
                pathlib.Path(value).mkdir(parents=True, exist_ok=True)
        if shell == "bash":
            command = ["bash", "--noprofile", "--norc"]
            if interactive:
                command += ["-ic", f'source "{tree}/entry/bash.sh"; exit 0']
            else:
                command += ["-c", f'source "{tree}/entry/bash.sh"']
        else:
            command = ["zsh", "-df"]
            command += ["-ic" if interactive else "-c", f'source "{tree}/entry/zshenv"; ' + (f'source "{tree}/entry/zsh.sh"; exit 0' if interactive else ':')]

        samples: list[float] = []
        for index in range(RUNS + 3):
            start = time.perf_counter()
            subprocess.run(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            elapsed = (time.perf_counter() - start) * 1000
            if index >= 3:
                samples.append(elapsed)
        return statistics.median(samples)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: startup-benchmark.py BASELINE CANDIDATE", file=sys.stderr)
        return 64
    baseline, candidate = map(pathlib.Path, sys.argv[1:])
    failed = False
    for shell in ("bash", "zsh"):
        for label, interactive in (("layer0", False), ("interactive", True)):
            old = measure(baseline, shell, interactive)
            new = measure(candidate, shell, interactive)
            delta = new - old
            percent = (delta / old * 100) if old else 0
            print(f"{shell:4} {label:11} baseline={old:7.2f}ms candidate={new:7.2f}ms delta={delta:+7.2f}ms ({percent:+.1f}%)")
            if new > 2000 or (delta > 10 and percent > 15):
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
