#!/usr/bin/env python3
"""Replay eget's release-asset selection for every eget.toml entry, per arch.

eget picks a release asset by applying each asset filter in turn and then its
native OS/arch detector. A filter that leaves exactly one asset, or that equals
an asset's full name, wins immediately without any architecture check. So a
filter that is right on one architecture can silently select another
architecture's binary. This test replays the selection offline for both
supported architectures against recorded asset-name lists.

Fixtures live in tests/fixtures/eget-assets/ and are keyed by repo and pinned
tag. After bumping a tag in eget.toml, record the new release's asset names:

    python3 tests/eget-selection.py --refresh

The detector logic mirrors eget v1.3.4 (detect.go). The test asserts that
installers/install-eget.sh still pins that version.
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import subprocess
import sys
import tomllib
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "eget-assets"
SIMULATED_EGET_VERSION = "1.3.4"


# --- eget v1.3.4 detection (detect.go) ---------------------------------------

OS_LINUX = re.compile(r"(?i)(linux|ubuntu)")
OS_LINUX_ANTI = re.compile(r"(?i)(android)")
OS_LINUX_PRIORITY = re.compile(r"\.appimage$")
FOREIGN_OS = {
    "darwin": re.compile(r"(?i)(darwin|mac.?(os)?|osx)"),
    "windows": re.compile(r"(?i)([^r]win|windows)"),
    "netbsd": re.compile(r"(?i)(netbsd)"),
    "freebsd": re.compile(r"(?i)(freebsd)"),
    "openbsd": re.compile(r"(?i)(openbsd)"),
    "android": re.compile(r"(?i)(android)"),
    "illumos": re.compile(r"(?i)(illumos)"),
    "solaris": re.compile(r"(?i)(solaris)"),
    "plan9": re.compile(r"(?i)(plan9)"),
}
ARCH = {
    "amd64": re.compile(r"(?i)(x64|amd64|x86(-|_)?64)"),
    "386": re.compile(r"(?i)(x32|amd32|x86(-|_)?32|i?386)"),
    "arm": re.compile(r"(?i)(arm32|armv6|arm\b)"),
    "arm64": re.compile(r"(?i)(arm64|armv8|aarch64)"),
    "riscv64": re.compile(r"(?i)(riscv64)"),
}
GOARCH = {"x86_64": "amd64", "aarch64": "arm64"}
METADATA = re.compile(r"(?i)(\.(sha256|sha256sum|sha512|sig|asc|pem|sbom|json|txt|intoto\.jsonl)$|sbom|checksums?)")


class Ambiguous(Exception):
    """eget would prompt interactively (or fail without a terminal)."""


class NotFound(Exception):
    """eget would exit with no matching asset."""


def single_asset(assets: list[str], asset: str, anti: bool) -> tuple[str | None, list[str]]:
    candidates = []
    for a in assets:
        base = posixpath.basename(a)
        if not anti and base == asset:
            return a, []
        if not anti and asset in base:
            candidates.append(a)
        if anti and asset not in base:
            candidates.append(a)
    if len(candidates) == 1:
        return candidates[0], []
    if candidates:
        return None, candidates
    raise NotFound(f"asset `{asset}` not found")


def system(assets: list[str], goarch: str) -> tuple[str | None, list[str]]:
    arch = ARCH[goarch]
    priority, matches, candidates, every = [], [], [], []
    for a in assets:
        if a.endswith(".sha256") or a.endswith(".sha256sum"):
            continue
        if OS_LINUX_ANTI.search(a):
            os_match, extra = False, False
        else:
            os_match, extra = bool(OS_LINUX.search(a)), bool(OS_LINUX_PRIORITY.search(a))
        if extra:
            priority.append(a)
        if os_match and arch.search(a):
            matches.append(a)
        if os_match:
            candidates.append(a)
        every.append(a)
    for group in (priority, matches, candidates):
        if len(group) == 1:
            return group[0], []
        if len(group) > 1:
            return None, group
    if len(every) == 1:
        return every[0], []
    if not every:
        raise NotFound("no candidates found")
    return None, every


def select(assets: list[str], filters: list[str], goarch: str) -> str:
    for f in filters:
        anti = f.startswith("^")
        choice, candidates = single_asset(assets, f[1:] if anti else f, anti)
        if not candidates:
            return choice
        assets = candidates
    choice, candidates = system(assets, goarch)
    if not candidates:
        return choice
    raise Ambiguous(f"{len(candidates)} candidates: {', '.join(sorted(candidates))}")


# --- correctness of a selection ----------------------------------------------

def foreign_os(base: str) -> str | None:
    if OS_LINUX.search(base):
        return None
    for os_name, rx in FOREIGN_OS.items():
        if rx.search(base):
            return os_name
    return None


def arch_tokens(base: str) -> set[str]:
    return {name for name, rx in ARCH.items() if rx.search(base)}


def verify_choice(choice: str, assets: list[str], goarch: str) -> str | None:
    """Return why `choice` is wrong for linux/goarch, else None."""
    base = posixpath.basename(choice)
    if METADATA.search(base):
        return "selected a checksum/signature/metadata file"
    os_name = foreign_os(base)
    if os_name:
        return f"selected a {os_name} asset"
    tokens = arch_tokens(base)
    if tokens and goarch not in tokens:
        return f"selected a {'/'.join(sorted(tokens))} asset"
    if not tokens:
        # An architecture-neutral name is only right when the release has no
        # asset specific to this architecture (e.g. wsl2-ssh-agent on x86_64,
        # but not on aarch64 where wsl2-ssh-agent-arm64 exists).
        specific = sorted(
            a for a in assets
            if not METADATA.search(posixpath.basename(a))
            and not foreign_os(posixpath.basename(a))
            and goarch in arch_tokens(posixpath.basename(a))
        )
        if specific:
            return f"selected an architecture-neutral asset although {', '.join(specific)} exists"
    return None


# --- repository data ---------------------------------------------------------

def fixture_path(repo: str, tag: str) -> Path:
    return FIXTURES / f"{repo.replace('/', '__')}@{tag}.txt"


def load_manifest() -> dict[str, dict]:
    with (ROOT / "eget.toml").open("rb") as fh:
        data = tomllib.load(fh)
    return {k: v for k, v in data.items() if k != "global"}


def registry_rows() -> list[dict]:
    """eget-method tools, their repo override, arches, and per-arch asset args."""
    script = r"""
set -euo pipefail
export DOTFILES_DIR="$1"
source "$DOTFILES_DIR/lib/runtime.sh"
source "$DOTFILES_DIR/lib/registry.sh"
for name in "${!TOOL_METHOD[@]}"; do
    [[ "${TOOL_METHOD[$name]}" == eget ]] || continue
    for arch in x86_64 aarch64; do
        args="$(DOTFILES_TEST_ARCH="$arch" tool_eget_asset_args "$name" | paste -sd $'\x1f' -)"
        printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${TOOL_EGET_REPO[$name]:-}" "${TOOL_ARCHES[$name]}" "$arch" "$args"
    done
done
"""
    out = subprocess.run(["bash", "-c", script, "bash", str(ROOT)],
                         check=True, capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        name, repo, arches, arch, args = line.split("\t")
        rows.append({"name": name, "repo": repo, "arches": arches.split(","),
                     "arch": arch, "args": [a for a in args.split("\x1f") if a]})
    return rows


def cli_filters(args: list[str]) -> list[str]:
    filters, it = [], iter(args)
    for a in it:
        if a == "--asset":
            filters.append(next(it))
        else:
            raise ValueError(f"unsupported eget argument from tool_eget_asset_args: {a}")
    return filters


def installer_eget_version() -> str:
    text = (ROOT / "installers" / "install-eget.sh").read_text()
    m = re.search(r'^EGET_VERSION="([^"]+)"', text, re.M)
    return m.group(1) if m else ""


# --- refresh -----------------------------------------------------------------

def github_token() -> str:
    for var in ("GITHUB_TOKEN", "GH_TOKEN"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        return subprocess.run(["gh", "auth", "token"], check=True, capture_output=True,
                              text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def github_get(url: str, token: str):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                               "User-Agent": "dotfiles-eget-selection"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def refresh(manifest: dict[str, dict]) -> int:
    token = github_token()
    FIXTURES.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for repo, entry in sorted(manifest.items()):
        tag = entry["tag"]
        path = fixture_path(repo, tag)
        wanted.add(path.name)
        release = github_get(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", token)
        names, page = [], 1
        while True:
            batch = github_get(f"{release['assets_url']}?per_page=100&page={page}", token)
            names += [a["name"] for a in batch]
            if len(batch) < 100:
                break
            page += 1
        path.write_text(f"# {repo} {tag} (recorded by tests/eget-selection.py --refresh)\n"
                        + "\n".join(sorted(names)) + "\n")
        print(f"recorded {len(names):3d} assets  {repo}@{tag}")
    for stale in FIXTURES.glob("*.txt"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed stale {stale.name}")
    return 0


# --- check -------------------------------------------------------------------

def check(manifest: dict[str, dict]) -> int:
    failures: list[str] = []
    version = installer_eget_version()
    if version != SIMULATED_EGET_VERSION:
        failures.append(f"installers/install-eget.sh pins eget {version or '?'}, but this test "
                        f"simulates {SIMULATED_EGET_VERSION}; re-verify detect.go and update it")

    by_basename = {repo.rsplit("/", 1)[1]: repo for repo in manifest}
    covered = set()
    for row in registry_rows():
        repo = row["repo"] or by_basename.get(row["name"], "")
        if repo not in manifest:
            failures.append(f"{row['name']}: no eget.toml entry")
            continue
        covered.add(repo)
        if row["arch"] not in row["arches"]:
            continue
        entry = manifest[repo]
        fixture = fixture_path(repo, entry["tag"])
        if not fixture.exists():
            failures.append(f"{row['name']}: no asset fixture for {repo}@{entry['tag']}; "
                            "run: python3 tests/eget-selection.py --refresh")
            continue
        assets = [line.strip() for line in fixture.read_text().splitlines()
                  if line.strip() and not line.startswith("#")]
        filters = cli_filters(row["args"]) if row["args"] else list(entry.get("asset_filters", []))
        goarch = GOARCH[row["arch"]]
        label = f"{row['name']:<15} {row['arch']:<8}"
        try:
            choice = select(assets, filters, goarch)
        except (Ambiguous, NotFound) as exc:
            failures.append(f"{label} {exc}  (filters: {filters})")
            continue
        reason = verify_choice(choice, assets, goarch)
        if reason:
            failures.append(f"{label} {reason}: {choice}  (filters: {filters})")
        else:
            print(f"ok  {label} {choice}")

    for repo in sorted(set(manifest) - covered):
        failures.append(f"{repo}: eget.toml entry has no eget-method registry tool")

    if failures:
        print("\n".join(f"FAIL: {f}" for f in failures), file=sys.stderr)
        return 1
    print("eget-selection: ok")
    return 0


def main(argv: list[str]) -> int:
    manifest = load_manifest()
    if argv[1:] == ["--refresh"]:
        return refresh(manifest)
    if argv[1:]:
        print("usage: eget-selection.py [--refresh]", file=sys.stderr)
        return 2
    return check(manifest)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
