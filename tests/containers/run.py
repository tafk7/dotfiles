#!/usr/bin/env python3
"""Run container scenarios against a commit, in throwaway Docker containers: dotfiles' own, or another
repository's (`--name`, `--scenarios`), which uses this file as its plumbing.

    python3 tests/containers/run.py --list
    python3 tests/containers/run.py --out DIR [--only NAME…] [--slow] [--commit REV] [--baseline REV]
                                    [--claude PATH] [--codex PATH] [--opencode PATH] [--keep-images] [--jobs N]
                                    [--name NAME --scenarios DIR] [--with NAME=PATH[@REV]…]

Another repository's scenarios run through this file: `--name` names the repository in the results,
`--scenarios` is its scenario directory, `--repo` its checkout, and `--with` bundles further
repositories its scenarios clone (`ctx.clone(..., repo=NAME)`).

A commit is tested, never the working tree: uncommitted changes are not in the run (a warning
says so). The quick scenarios run with no network; `--slow` adds the real installs, which
download from the network. The agent CLIs default to the `claude` and `codex` on PATH; they are
mounted read-only into the containers that need them, and no model is called (stand-in servers
answer inside the container). Results: DIR/results.jsonl (lib/results.py) and DIR/logs/. The last
line printed is the summary; the exit status is 0 only when every scenario passed.
"""

import argparse
import concurrent.futures
import datetime
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from lib import results  # noqa: E402
from lib.bundle import make_bundle, resolve  # noqa: E402
from lib.container import Docker  # noqa: E402
from lib.context import Context, codex_package, tool_version  # noqa: E402

REPO = HERE.parents[1]


def load_scenarios(directory: Path = HERE / "scenarios") -> dict:
    sys.path.insert(0, str(directory))  # the scenarios' shared helpers (`_install`)
    found = {}
    for path in sorted(directory.glob("*.py")):
        if path.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(f"scenario_{path.stem}", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        found[module.NAME] = module
    return found


def run_one(module, make_context, out: Path, scrub=lambda text: text) -> dict:
    name = module.NAME
    log_rel = f"logs/{name.replace('/', '-')}.log"
    log_path = out / log_rel
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    with log_path.open("w") as log_file:
        def log(text):
            log_file.write(scrub(text).rstrip("\n") + "\n")
            log_file.flush()
        try:
            if getattr(module, "INTERFACE", None) != results.INTERFACE:
                raise RuntimeError(f"written for interface {getattr(module, 'INTERFACE', None)}, "
                                   f"this is {results.INTERFACE}")
            ctx = make_context(module, log)
            detail = module.run(ctx) or "ok"
            result = "pass"
        except results.Failure as failure:
            result, detail = "fail", str(failure)
            log(f"[fail] {failure}")
        except Exception as error:  # an error is a result too: never a skip
            result, detail = "error", f"{type(error).__name__}: {error}"
            log("[error]\n" + traceback.format_exc())
    return results.scenario_line(name, result, time.monotonic() - started, scrub(detail).splitlines()[0][:300], log_rel)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--only", nargs="+", default=[])
    parser.add_argument("--slow", action="store_true", help="include the slow scenarios (network installs)")
    parser.add_argument("--repo", type=Path, default=REPO, help="the dotfiles repository (default: this one)")
    parser.add_argument("--commit", default="HEAD")
    parser.add_argument("--baseline", help="the deployed commit, for dotfiles/update (default: origin/main's merge-base)")
    parser.add_argument("--claude", type=Path, default=shutil.which("claude"))
    parser.add_argument("--codex", type=Path, default=shutil.which("codex"))
    parser.add_argument("--opencode", type=Path, default=shutil.which("opencode"))
    parser.add_argument("--name", default="dotfiles", help="the repository under test, as results name it")
    parser.add_argument("--scenarios", type=Path, default=HERE / "scenarios")
    parser.add_argument("--with", dest="extra", action="append", default=[], metavar="NAME=PATH[@REV]",
                        help="another repository the scenarios clone, at REV (default HEAD)")
    parser.add_argument("--keep-images", action="store_true")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args(argv)

    scenarios = load_scenarios(args.scenarios.resolve())
    if args.list:
        for name, module in scenarios.items():
            print(f"{name}\t{'slow' if module.SLOW else 'quick'}")
        return 0
    if args.out is None:
        parser.error("--out is required")
    unknown = [name for name in args.only if name not in scenarios]
    if unknown:
        parser.error(f"unknown scenarios: {', '.join(unknown)}")
    chosen = [scenarios[name] for name in (args.only or scenarios) if args.only or args.slow or not scenarios[name].SLOW]

    repo = args.repo.resolve()
    commit = resolve(repo, args.commit)
    if subprocess.run(["git", "-C", str(repo), "status", "--porcelain"], capture_output=True, text=True).stdout.strip():
        print(f"warning: {repo} has uncommitted changes; the run tests {commit[:12]} only", file=sys.stderr)
    baseline = None
    if any(getattr(m, "USES_BASELINE", False) for m in chosen):
        rev = args.baseline or subprocess.run(["git", "-C", str(repo), "merge-base", commit, "origin/main"],
                                              capture_output=True, text=True).stdout.strip()
        baseline = resolve(repo, rev) if rev else None

    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    run_id = uuid.uuid4().hex[:10]
    binaries = {tool: path.resolve() for tool, path in
                (("claude", args.claude), ("codex", args.codex), ("opencode", args.opencode)) if path}
    extras = {}
    for value in args.extra:
        name, _, rest = value.partition("=")
        path, _, rev = rest.partition("@")
        extras[name] = (Path(path).expanduser().resolve(), resolve(Path(path).expanduser(), rev or "HEAD"))
    with tempfile.TemporaryDirectory(prefix="testbed-") as scratch:
        work = Path(scratch)
        refs = {"candidate": commit, **({"baseline": baseline} if baseline else {})}
        bundle = make_bundle(repo, work / "repo.bundle", refs)
        extra_bundles = {name: (make_bundle(path, work / f"{name}.bundle", {"candidate": rev}), rev)
                         for name, (path, rev) in extras.items()}
        run_log = (out / "logs" / "run.log")
        run_log.parent.mkdir(parents=True, exist_ok=True)
        with run_log.open("w") as run_file:
            def run_logger(text):
                run_file.write(text.rstrip("\n") + "\n")
                run_file.flush()
            inputs = [bundle, HERE / "lib", *binaries.values(), *(b for b, _ in extra_bundles.values())]
            if "codex" in binaries and codex_package(binaries["codex"]):
                inputs.append(codex_package(binaries["codex"]))
            docker = Docker(run_id, inputs=inputs, log=run_logger)
            tools = {"docker": docker._call(["version", "--format", "{{.Server.Version}}"]).stdout.strip()}
            tools.update({tool: tool_version(path) for tool, path in binaries.items()})
            header = {"repo": args.name, "commit": commit, "baseline": baseline, "tools": tools, "run": run_id,
                      "with": {name: rev for name, (_, rev) in extra_bundles.items()},
                      "started": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}

            image_cache, image_lock = {}, threading.Lock()

            def make_context(module, log):
                missing = [tool for tool in getattr(module, "NEEDS", ()) if tool not in binaries]
                if missing:
                    raise RuntimeError(f"needs {', '.join(missing)}, not given (--{missing[0]} PATH)")
                if getattr(module, "USES_BASELINE", False) and not baseline:
                    raise RuntimeError("needs a baseline commit (--baseline REV)")
                scenario_docker = Docker.__new__(Docker)
                scenario_docker.__dict__.update(docker.__dict__)
                scenario_docker.log = log
                scenario_docker.inputs = list(docker.inputs)
                return Context(scenario_docker, work=work, bundle=bundle, commit=commit, baseline=baseline, repo=repo,
                               binaries=binaries, log=log, image_cache=image_cache, image_lock=image_lock,
                               extras=extra_bundles)

            lines = []
            try:
                with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
                    futures = [pool.submit(run_one, module, make_context, out, docker.scrub) for module in chosen]
                    for future in futures:
                        line = future.result()
                        lines.append(line)
                        print(f"{line['result']:5} {line['name']} ({line['seconds']}s) {line['detail']}", flush=True)
            finally:
                header["images"] = dict(docker.images)
                removed = docker.cleanup(keep_images=args.keep_images)
                run_logger(f"cleanup removed: {removed}")
    results.write(out / "results.jsonl", header, lines)
    print(results.summary(args.name, commit, lines))
    return 0 if lines and all(line["result"] == "pass" for line in lines) else 1


if __name__ == "__main__":
    sys.exit(main())
