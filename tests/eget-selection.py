#!/usr/bin/env python3
"""Replay eget's release-asset selection for every eget.toml entry, per arch.

eget picks a release asset by applying each asset filter in turn and then its
native OS/arch detector. A filter that leaves exactly one asset, or that equals
an asset's full name, wins immediately without any architecture check. So a
filter that is right on one architecture can silently select another
architecture's binary. This test replays the selection offline for both
supported architectures against recorded asset-name lists.

Fixtures live in tests/fixtures/eget-assets/ and are keyed by repo and pinned
tag. `dotfiles bump` records a new release's asset names and regenerates the
eget rows of versions.lock (lib/lockgen.py); `--refresh` here does the same
for eget.toml's tags as they stand:

    python3 tests/eget-selection.py --refresh

versions.lock records, per tool and architecture, the asset this selection
picks, its SHA-256, the file to extract, and the extracted binary's SHA-256
(its installed identity). The installer downloads exactly that asset from the
release's download URL, so installing never calls the GitHub API (whose
anonymous limit is 60 requests an hour per address, and fresh machines and CI
runners share addresses). --refresh downloads only assets whose rows are
missing or incomplete, keeps every other component's rows, and uses
GITHUB_TOKEN, GH_TOKEN or `gh auth token` when available. The check fails when
eget.toml's tags and versions.lock disagree.

The detector logic mirrors eget v1.3.4 (detect.go). The test asserts that
versions.lock still pins that version.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from lockgen import (SIMULATED_EGET_VERSION, installer_eget_version, load_manifest,  # noqa: E402
                     read_lock, refresh, registry_rows, selections)


# --- check -------------------------------------------------------------------

def check(manifest: dict[str, dict]) -> int:
    failures: list[str] = []
    version = installer_eget_version()
    if version != SIMULATED_EGET_VERSION:
        failures.append(f"versions.lock pins eget {version or '?'}, but this test "
                        f"simulates {SIMULATED_EGET_VERSION}; re-verify detect.go and update it")

    _, lock = read_lock()
    eget_names = {row["name"] for row in registry_rows()}
    expected = set()
    covered = set()
    for row, repo, label, choice, failure in selections(manifest):
        if repo:
            covered.add(repo)
        if failure:
            failures.append(failure)
            continue
        print(f"ok  {label} {choice}")
        key = (row["name"], row["arch"])
        expected.add(key)
        locked = lock.get(key)
        stale = "run: dotfiles bump --refresh"
        if not locked:
            failures.append(f"{label} not in versions.lock; {stale}")
        elif locked["want"] != manifest[repo]["tag"] or locked["artifact"] != choice or locked["source"] != repo:
            failures.append(f"{label} versions.lock has {locked['artifact']}@{locked['want']}, "
                            f"eget.toml selects {choice}@{manifest[repo]['tag']}; {stale}")
        elif not re.fullmatch(r"[0-9a-f]{64}", locked["sha256"]) or not locked["member"] \
                or not re.fullmatch(r"sha256:[0-9a-f]{64}", locked["identity"]):
            failures.append(f"{label} malformed versions.lock row")
    for name, arch in sorted(k for k in set(lock) - expected if k[0] in eget_names):
        failures.append(f"versions.lock has a row no tool selects: {name} {arch}")

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
