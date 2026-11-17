"""A git bundle of the commits under test, made without touching the repository they come from.

`git bundle` needs refs, and a raw commit has none; writing a ref into the caller's repository
would be a side effect. So the commits are cloned into a throwaway repository, given refs there
(`refs/heads/candidate`, `refs/heads/baseline`), and bundled from it. The bundle carries the
commits' history, so a scenario can install one commit and move to the other with git.
"""

import subprocess
import tempfile
from pathlib import Path


def git(*args, cwd=None) -> str:
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout.strip()


def resolve(repo: Path, rev: str) -> str:
    return git("-C", str(repo), "rev-parse", "--verify", f"{rev}^{{commit}}")


def make_bundle(repo: Path, dest: Path, refs: dict[str, str]) -> Path:
    """Bundle each NAME -> commit of REPO into DEST as refs/heads/NAME, with HEAD at the first."""
    with tempfile.TemporaryDirectory(prefix="testbed-bundle-") as scratch:
        clone = Path(scratch) / "repo"
        git("clone", "-q", "--no-checkout", "--no-local", str(repo), str(clone))
        for name, commit in refs.items():
            git("-C", str(clone), "update-ref", f"refs/heads/{name}", commit)
        first = next(iter(refs))
        git("-C", str(clone), "symbolic-ref", "HEAD", f"refs/heads/{first}")
        git("-C", str(clone), "bundle", "create", str(dest), "HEAD", *(f"refs/heads/{name}" for name in refs))
    dest.chmod(0o644)  # docker cp keeps the host's owner; a container user must still read it
    return dest
