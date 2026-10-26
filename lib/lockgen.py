#!/usr/bin/env python3
"""versions.lock generation: release data, eget's asset selection, and lock rows.

Used by `dotfiles bump` (lib/bump.py) and the selection check
(tests/eget-selection.py).

eget picks a release asset by applying each asset filter in turn and then its
native OS/arch detector. A filter that leaves exactly one asset, or that equals
an asset's full name, wins immediately without any architecture check. So a
filter that is right on one architecture can silently select another
architecture's binary. select() replays the selection offline for both
supported architectures against recorded asset-name lists in
tests/fixtures/eget-assets/, keyed by repo and pinned tag.

versions.lock records, per tool and architecture, the asset this selection
picks, its SHA-256, the file to extract, and the extracted binary's SHA-256
(its installed identity). The installer downloads exactly that asset from the
release's download URL, so installing never calls the GitHub API. refresh()
records asset lists for eget.toml's tags and writes the eget rows, downloading
only assets whose rows are missing or incomplete and keeping every other
component's rows; it uses GITHUB_TOKEN, GH_TOKEN or `gh auth token` when
available.

Network reads go through fetch(), github_get() and head(). With
DOTFILES_FETCH_FIXTURES set, they are served from that directory instead:
the URL, percent-encoded, names the file (with .json for github_get and
.headers for head), so tests run offline against recorded releases.

The detector logic mirrors eget v1.3.4 (detect.go).
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import subprocess
import sys
import hashlib
import io
import tarfile
import tomllib
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "eget-assets"
LOCK = ROOT / "versions.lock"
LOCK_FIELDS = ["component", "arch", "want", "source", "artifact", "sha256", "member", "identity"]
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
    """eget-method tools, their repo override, arches, per-arch asset args,
    binary and companions."""
    script = r"""
set -euo pipefail
export DOTFILES_DIR="$1"
source "$DOTFILES_DIR/lib/runtime.sh"
source "$DOTFILES_DIR/lib/registry.sh"
for name in "${!TOOL_METHOD[@]}"; do
    [[ "${TOOL_METHOD[$name]}" == eget ]] || continue
    for arch in x86_64 aarch64; do
        args="$(DOTFILES_TEST_ARCH="$arch" tool_eget_asset_args "$name" | paste -sd $'\x1f' -)"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "${TOOL_EGET_REPO[$name]:-}" "${TOOL_ARCHES[$name]}" "$arch" "$args" \
            "${TOOL_BINARY[$name]}" "${TOOL_COMPANIONS[$name]:-}"
    done
done
"""
    out = subprocess.run(["bash", "-c", script, "bash", str(ROOT)],
                         check=True, capture_output=True, text=True).stdout
    rows = []
    for line in out.splitlines():
        name, repo, arches, arch, args, binary, companions = line.split("\t")
        rows.append({"name": name, "repo": repo, "arches": arches.split(","),
                     "arch": arch, "args": [a for a in args.split("\x1f") if a],
                     "binary": binary, "companions": companions.split()})
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
    """The eget release versions.lock pins, without its v."""
    _, rows = read_lock()
    row = rows.get(("eget", "x86_64"))
    return row["want"].removeprefix("v") if row else ""


# --- selection per tool and architecture ------------------------------------

def selections(manifest: dict[str, dict]):
    """Yield (row, repo, label, choice, failure) for every eget-method tool and
    architecture it supports; failure is a message when there is no choice.
    Rows whose repo has no eget.toml entry yield repo None."""
    by_basename = {repo.rsplit("/", 1)[1]: repo for repo in manifest}
    for row in registry_rows():
        repo = row["repo"] or by_basename.get(row["name"], "")
        label = f"{row['name']:<15} {row['arch']:<8}"
        if repo not in manifest:
            yield row, None, label, None, f"{row['name']}: no eget.toml entry"
            continue
        if row["arch"] not in row["arches"]:
            continue
        entry = manifest[repo]
        fixture = fixture_path(repo, entry["tag"])
        if not fixture.exists():
            yield row, repo, label, None, (f"{row['name']}: no asset fixture for {repo}@{entry['tag']}; "
                                           "run: dotfiles bump --refresh")
            continue
        assets = [line.strip() for line in fixture.read_text().splitlines()
                  if line.strip() and not line.startswith("#")]
        filters = cli_filters(row["args"]) if row["args"] else list(entry.get("asset_filters", []))
        goarch = GOARCH[row["arch"]]
        try:
            choice = select(assets, filters, goarch)
        except (Ambiguous, NotFound) as exc:
            yield row, repo, label, None, f"{label} {exc}  (filters: {filters})"
            continue
        reason = verify_choice(choice, assets, goarch)
        if reason:
            yield row, repo, label, None, f"{label} {reason}: {choice}  (filters: {filters})"
        else:
            yield row, repo, label, choice, None


# --- the lock ----------------------------------------------------------------

def read_lock() -> tuple[list[str], dict[tuple[str, str], dict]]:
    """The lock's leading comment lines, and its rows keyed by (component, arch)."""
    header, rows = [], {}
    if not LOCK.exists():
        return header, rows
    for line in LOCK.read_text().splitlines():
        if line.startswith("#"):
            if not rows:
                header.append(line)
            continue
        if not line.strip():
            continue
        values = line.split("\t")
        rows[(values[0], values[1])] = dict(zip(LOCK_FIELDS, values))
    return header, rows


def write_lock(header: list[str], rows: dict[tuple[str, str], dict]) -> None:
    lines = list(header)
    for key in sorted(rows, key=lambda k: (k[0].lower(), k[1])):
        lines.append("\t".join(rows[key][f] for f in LOCK_FIELDS))
    LOCK.write_text("\n".join(lines) + "\n")


def member_bytes(data: bytes, asset: str, member: str) -> bytes:
    """The bytes eget installs: the archive member, or the bare binary."""
    if member == "-":
        return data
    if asset.lower().endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            return z.read(member)
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        extracted = t.extractfile(member)
        if extracted is None:
            raise ValueError(f"{asset}: {member} is not a regular file")
        return extracted.read()


def download_url(repo: str, tag: str, asset: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{asset}"


def executables(data: bytes, asset: str) -> list[str] | None:
    """Executable regular files in an archive, or None for a bare binary."""
    lower = asset.lower()
    if lower.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            return [i.filename for i in z.infolist()
                    if not i.is_dir() and (i.external_attr >> 16) & 0o111]
    if any(lower.endswith(ext) for ext in (".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tar.xz", ".txz", ".tar")):
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            return [m.name for m in t.getmembers() if m.isfile() and m.mode & 0o111]
    return None


def archive_member(data: bytes, asset: str, binary: str, companions: list[str]) -> str:
    """The member eget would install as `binary` (by name, else the only
    executable); companions must be present by name."""
    members = executables(data, asset)
    if members is None:
        if companions:
            raise ValueError(f"{asset} is a bare binary but companions {companions} are declared")
        return "-"
    named = [m for m in members if posixpath.basename(m) == binary]
    for companion in companions:
        if not any(posixpath.basename(m) == companion for m in members):
            raise ValueError(f"{asset} has no companion `{companion}` among {members}")
    if len(named) == 1:
        return named[0]
    if not named and len(members) == 1:
        return members[0]
    raise ValueError(f"{asset}: cannot tell which of {members} is `{binary}`")


def _fixture(url: str, suffix: str = "") -> Path | None:
    root = os.environ.get("DOTFILES_FETCH_FIXTURES")
    if not root:
        return None
    path = Path(root) / (urllib.parse.quote(url, safe="") + suffix)
    if not path.exists():
        raise FileNotFoundError(f"no recorded response for {url} ({path.name})")
    return path


def fetch(url: str) -> bytes:
    recorded = _fixture(url)
    if recorded:
        return recorded.read_bytes()
    req = urllib.request.Request(url, headers={"User-Agent": "dotfiles-lockgen"})
    with urllib.request.urlopen(req, timeout=300) as resp:
        return resp.read()


def head(url: str) -> dict[str, str]:
    """A HEAD request's headers, lower-cased."""
    recorded = _fixture(url, ".headers")
    if recorded:
        return {k.lower(): v for k, v in json.loads(recorded.read_text()).items()}
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "dotfiles-lockgen"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return {k.lower(): v for k, v in resp.headers.items()}


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
    recorded = _fixture(url, ".json")
    if recorded:
        return json.loads(recorded.read_text())
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json",
                                               "User-Agent": "dotfiles-lockgen"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def refresh(manifest: dict[str, dict]) -> int:
    token = github_token()
    FIXTURES.mkdir(parents=True, exist_ok=True)
    wanted = set()
    header, old_rows = read_lock()
    old_tags = {(r["source"], r["want"]) for r in old_rows.values()}
    digests: dict[tuple[str, str], str] = {}
    for repo, entry in sorted(manifest.items()):
        tag = entry["tag"]
        path = fixture_path(repo, tag)
        wanted.add(path.name)
        if path.exists() and (repo, tag) in old_tags \
                and all(r["want"] == tag for r in old_rows.values() if r["source"] == repo):
            continue  # recorded for this tag, and the lock already follows it
        release = github_get(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", token)
        names, page = [], 1
        while True:
            batch = github_get(f"{release['assets_url']}?per_page=100&page={page}", token)
            names += [a["name"] for a in batch]
            digests.update({(repo, a["name"]): a.get("digest") or "" for a in batch})
            if len(batch) < 100:
                break
            page += 1
        path.write_text(f"# {repo} {tag} (recorded by lib/lockgen.py)\n"
                        + "\n".join(sorted(names)) + "\n")
        print(f"recorded {len(names):3d} assets  {repo}@{tag}")
    for stale in FIXTURES.glob("*.txt"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed stale {stale.name}")

    eget_names = {row["name"] for row in registry_rows()}
    lock = {key: row for key, row in old_rows.items() if key[0] not in eget_names}
    failures = []
    for row, repo, label, choice, failure in selections(manifest):
        if failure:
            failures.append(failure)
            continue
        tag = manifest[repo]["tag"]
        key = (row["name"], row["arch"])
        previous = old_rows.get(key)
        if previous and previous["want"] == tag and previous["artifact"] == choice \
                and previous["source"] == repo and previous["identity"].startswith("sha256:"):
            lock[key] = previous
            continue
        data = fetch(download_url(repo, tag, choice))
        sha256 = hashlib.sha256(data).hexdigest()
        published = digests.get((repo, choice), "")
        if published and published != f"sha256:{sha256}":
            failures.append(f"{label} {choice}: downloaded sha256 {sha256}, GitHub publishes {published}")
            continue
        if previous and previous["want"] == tag and previous["artifact"] == choice and previous["sha256"] != sha256:
            failures.append(f"{label} {choice}: downloaded sha256 {sha256}, versions.lock has {previous['sha256']}")
            continue
        try:
            member = archive_member(data, choice, row["binary"], row["companions"])
            identity = hashlib.sha256(member_bytes(data, choice, member)).hexdigest()
        except (ValueError, KeyError) as exc:
            failures.append(f"{label} {exc}")
            continue
        lock[key] = {"component": row["name"], "arch": row["arch"], "want": tag, "source": repo,
                     "artifact": choice, "sha256": sha256, "member": member, "identity": f"sha256:{identity}"}
        print(f"locked   {label} {choice}  {member}")
    if failures:
        print("\n".join(f"FAIL: {f}" for f in failures), file=sys.stderr)
        print("versions.lock not written", file=sys.stderr)
        return 1
    write_lock(header, lock)
    print(f"wrote {LOCK.name}: {len(lock)} rows")
    return 0
