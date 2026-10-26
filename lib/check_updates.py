#!/usr/bin/env python3
"""Compare every pin with its source's newest release, and look up advisories.

    check-updates [--outdated] [--json | --records] [TOOL]

Covers every row of versions.lock (eget tools and the GitHub-released tools,
Node, the Rust toolchain, the AWS CLI, vim-plug, and sbx; npm follows Node)
and every Neovim plugin pinned in configs/init.vim. Advisories: GitHub's
published repository advisories newer than the pinned release, and Node
security releases newer than the pin. Unpinned components are listed as such.

Exit 1 when a lookup failed, 2 with --outdated when something is behind or has
an advisory, 0 otherwise. --records prints outcome records (lib/outcomes.sh)
for `dotfiles verify --latest`: behind is advisory, an advisory is health, a
failed lookup incomplete. Auth: GITHUB_TOKEN, GH_TOKEN, or `gh auth token`.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lockgen import ROOT, fetch, github_get, github_token, read_lock  # noqa: E402

PLUG_LINE = re.compile(r"^\s*Plug '([^']+)',\s*\{\s*'commit':\s*'([0-9a-f]{40})'", re.M)


def version_key(value: str) -> list:
    """Sort key for tags: numbers numerically, letters after (3.7c > 3.7)."""
    return [int(p) if p.isdigit() else p for p in re.findall(r"\d+|[a-z]+", value.lower().removeprefix("v"))]


def compare(pinned: str, latest: str) -> str:
    if pinned.removeprefix("v") == latest.removeprefix("v"):
        return "current"
    return "outdated" if version_key(pinned) < version_key(latest) else "ahead"


class Checker:
    def __init__(self) -> None:
        self.token = github_token()

    def gh(self, path: str):
        return github_get(f"https://api.github.com/{path}", self.token)

    def advisories_since(self, repo: str, pinned: str) -> list[str]:
        """Published repository advisories newer than the pinned release."""
        try:
            released = self.gh(f"repos/{repo}/releases/tags/{pinned}")["published_at"]
            listed = self.gh(f"repos/{repo}/security-advisories?state=published&per_page=100")
        except Exception:  # noqa: BLE001 - advisories are best effort
            return []
        return [f"{a['ghsa_id']} ({a.get('severity', '?')}): {a.get('summary', '')}"
                for a in listed if a.get("published_at", "") > released]

    def github_release(self, repo: str, pinned: str) -> dict:
        latest = self.gh(f"repos/{repo}/releases/latest")["tag_name"]
        return {"latest": latest, "status": compare(pinned, latest), "advisories": self.advisories_since(repo, pinned)}

    def commit(self, repo: str, pinned: str) -> dict:
        latest = self.gh(f"repos/{repo}/commits/HEAD")["sha"]
        return {"latest": latest, "status": "current" if latest == pinned else "outdated", "advisories": []}

    def node(self, pinned: str) -> dict:
        index = json.loads(fetch("https://nodejs.org/dist/index.json"))
        latest = next(e["version"] for e in index if e.get("lts"))
        major = pinned.removeprefix("v").split(".")[0]
        newer_fixes = [e["version"] for e in index if e.get("security") and e["version"].split(".")[0] == f"v{major}"
                       and version_key(e["version"]) > version_key(pinned)]
        return {"latest": latest, "status": compare(pinned, latest),
                "advisories": [f"security release {v} (Node {major})" for v in newer_fixes]}

    def rust(self, pinned: str) -> dict:
        manifest = tomllib.loads(fetch("https://static.rust-lang.org/dist/channel-rust-stable.toml").decode())
        latest = re.match(r"\d+\.\d+\.\d+", manifest["pkg"]["rustc"]["version"]).group(0)
        return {"latest": latest, "status": compare(pinned, latest), "advisories": []}

    def aws(self, pinned: str) -> dict:
        changelog = fetch("https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst").decode()
        latest = re.search(r"^(2\.\d+\.\d+)$", changelog, re.M).group(1)
        return {"latest": latest, "status": compare(pinned, latest), "advisories": []}

    def sbx(self, pinned: str) -> dict:
        found = []
        for arch in ("amd64", "arm64"):
            text = fetch(f"https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-{arch}/Packages").decode()
            found.append({m.group(1).split("-", 1)[0] for m in re.finditer(
                r"Package: docker-sbx\nVersion: (\S+)", text)})
        both = found[0] & found[1]
        latest = max(both, key=version_key) if both else "?"
        return {"latest": latest, "status": compare(pinned, latest) if both else "error", "advisories": []}


def pins() -> list[dict]:
    """Every pinned thing once: lock components (one row for per-arch pins),
    then Neovim plugins."""
    _, lock = read_lock()
    seen, out = set(), []
    for (component, _arch), row in sorted(lock.items()):
        if component in seen or component == "npm":
            continue
        seen.add(component)
        source = row["source"]
        if component == "vim-plug":
            kind = "commit"
        elif component in ("node", "rust", "aws-cli", "sbx"):
            kind = component
        elif "/" in source:
            kind = "github"
        else:
            continue
        out.append({"name": component, "kind": kind, "source": source, "pinned": row["want"]})
    for repo, commit in PLUG_LINE.findall((ROOT / "configs/init.vim").read_text()):
        out.append({"name": repo.rsplit("/", 1)[1], "kind": "commit", "source": repo, "pinned": commit})
    return out


def check(pin: dict, checker: Checker) -> dict:
    try:
        if pin["kind"] == "github":
            result = checker.github_release(pin["source"], pin["pinned"])
        elif pin["kind"] == "commit":
            result = checker.commit(pin["source"], pin["pinned"])
        else:
            result = getattr(checker, pin["kind"].replace("-cli", ""))(pin["pinned"])
    except Exception as exc:  # noqa: BLE001 - every lookup failure is reported
        result = {"latest": "?", "status": "error", "advisories": [], "error": str(exc)}
    return {**pin, **result}


def unpinned() -> list[str]:
    import subprocess
    script = ('export DOTFILES_DIR="$1"; source "$1/lib/runtime.sh"; source "$1/lib/registry.sh"; '
              'for n in "${REGISTRY_ORDER[@]}"; do [[ "$n" == packages:* || "${TOOL_POLICY[$n]}" == converge ]] || echo "$n"; done')
    return subprocess.run(["bash", "-c", script, "bash", str(ROOT)], capture_output=True, text=True).stdout.split()


def short(value: str) -> str:
    return value[:12] if re.fullmatch(r"[0-9a-f]{40}", value) else value


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="check-updates", description=__doc__.split("\n\n")[0])
    parser.add_argument("tool", nargs="?")
    parser.add_argument("--outdated", action="store_true", help="only pins that are behind or have advisories")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--json", action="store_true")
    output.add_argument("--records", action="store_true")
    args = parser.parse_args(argv)

    checker = Checker()
    selected = [p for p in pins() if not args.tool or args.tool in (p["name"], p["source"])]
    if args.tool and not selected:
        print(f"check-updates: no pin named {args.tool}", file=sys.stderr)
        return 1
    results = [check(p, checker) for p in selected]
    flagged = [r for r in results if r["status"] == "outdated" or r["advisories"]]
    shown = [r for r in results if not args.outdated or r in flagged or r["status"] == "error"]

    if args.records:
        for r in results:
            if r["status"] == "error":
                print(f"incomplete\tUpstream\t{r['name']}\trelease lookup failed")
            elif r["status"] == "outdated":
                print(f"advisory\tUpstream\t{r['name']}\t{short(r['latest'])} is available (pinned {short(r['pinned'])})")
            else:
                print(f"ok\tUpstream\t{r['name']}\t{short(r['pinned'])} is current")
            for advisory in r["advisories"]:
                print(f"health\tUpstream\t{r['name']}\t{advisory}")
        return 0
    if args.json:
        print(json.dumps(shown, indent=2))
    else:
        icons = {"current": "up to date", "outdated": "update available", "ahead": "ahead of release", "error": "check failed"}
        print(f"{'Pin':<22} {'Kind':<8} {'Pinned':<14} {'Latest':<14} Status")
        for r in shown:
            print(f"{r['name']:<22} {r['kind']:<8} {short(r['pinned']):<14} {short(r['latest']):<14} {icons[r['status']]}")
            for advisory in r["advisories"]:
                print(f"{'':<22} advisory: {advisory}")
        if not args.tool:
            names = unpinned()
            if names:
                print(f"\nNot pinned (the package manager or vendor updates them; dotfiles update --upgrade): {', '.join(names)}")
        if flagged:
            print("\nMove a pin with: dotfiles bump TOOL [VERSION], then dotfiles apply.")
    if any(r["status"] == "error" for r in results):
        return 1
    return 2 if args.outdated and flagged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
