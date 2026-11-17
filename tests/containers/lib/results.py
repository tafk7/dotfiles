"""The result format every part of the testbed writes and the gate reads.

`results.jsonl` in the run's output directory: a header line, then one line per scenario.

    {"interface": 1, "repo": "dotfiles", "commit": "SHA", "baseline": "SHA" | null,
     "tools": {"docker": "29.9.2", "claude": "2.1.321 sha256:…", …}, "images": {"TAG": "sha256:…"},
     "started": "ISO-8601"}
    {"name": "dotfiles/dry-run", "result": "pass", "seconds": 41.2, "detail": "…", "log": "logs/dotfiles-dry-run.log"}

`result` is one of RESULTS. There is no skip: a scenario that cannot run is an `error`, and the
gate treats `fail` and `error` alike. INTERFACE changes when a field changes meaning; a scenario
written for another interface is an `error`.
"""

import json
from pathlib import Path

INTERFACE = 1
RESULTS = ("pass", "fail", "error")


class Failure(Exception):
    """The scenario ran and found what it checks for wrong: `fail`, not `error`."""


def scenario_line(name: str, result: str, seconds: float, detail: str, log: str) -> dict:
    if result not in RESULTS:
        raise ValueError(f"result {result!r} is not one of {RESULTS}")
    return {"name": name, "result": result, "seconds": round(seconds, 1), "detail": detail, "log": log}


def write(path: Path, header: dict, lines: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as out:
        out.write(json.dumps({"interface": INTERFACE, **header}) + "\n")
        for line in lines:
            out.write(json.dumps(line) + "\n")


def read(path: Path) -> tuple[dict, list[dict]]:
    header, *lines = [json.loads(text) for text in path.read_text().splitlines() if text.strip()]
    if header.get("interface") != INTERFACE:
        raise ValueError(f"{path}: interface {header.get('interface')}, expected {INTERFACE}")
    return header, lines


def summary(repo: str, commit: str, lines: list[dict]) -> str:
    counts = {result: sum(1 for line in lines if line["result"] == result) for result in RESULTS}
    return (f"testbed {repo}: {counts['pass']} pass, {counts['fail']} fail, {counts['error']} error "
            f"({repo}@{commit[:12]})")
