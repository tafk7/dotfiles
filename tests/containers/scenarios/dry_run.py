"""dotfiles/dry-run: `setup.sh --bash --dry-run` on each supported Ubuntu changes nothing.

Setup: a clean container of 22.04, 24.04 and 26.04 (lib/images/clean.Dockerfile), no network,
the commit cloned to ~/dev/dotfiles as the sudo user `test`. Checks: the dry run exits 0, and a
listing of the filesystem (paths, types, modes, sizes, mtimes; outside /proc, /sys, /dev, /run,
/tmp and the clone) is the same before and after it, except for the dry run's own log
(~/.local/state/dotfiles/logs, the directories made to hold it, and the home folder's mtime).
Covers: setup's safety on every release.
"""

from lib.results import Failure

NAME = "dotfiles/dry-run"
SLOW = False
NETWORK = False
NEEDS = ()
INTERFACE = 1
RELEASES = ("22.04", "24.04", "26.04")

LISTING = (r"find / -xdev \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp "
           r"-o -path /var/tmp -o -path /home/test/dev \) -prune -o -printf '%p\t%y\t%m\t%s\t%T@\n' | LC_ALL=C sort")


HOME = "/home/test"
LOGS = f"{HOME}/.local/state/dotfiles/logs"


def listing(text: str) -> dict:
    entries = {}
    for line in text.splitlines():
        path, kind, mode, size, mtime = line.split("\t")
        entries[path] = (kind, mode, size, mtime)
    return entries


def unexpected_changes(before: dict, after: dict) -> list[str]:
    """Changed, added or removed paths, less the dry run's log and what holds it."""
    holders = {LOGS}
    parent = LOGS
    while parent != HOME:
        parent = parent.rsplit("/", 1)[0]
        holders.add(parent)
    changes = []
    for path in sorted(set(before) | set(after)):
        old, new = before.get(path), after.get(path)
        if old == new:
            continue
        if path == LOGS or path.startswith(LOGS + "/"):
            continue
        if path in holders and new is not None and new[0] == "d" and (old is None or old[:3] == new[:3]):
            continue  # made to hold the log, or only its mtime moved
        changes.append(f"{path}: {old} -> {new}")
    return changes


def run(ctx):
    passed = []
    for release in RELEASES:
        container = ctx.docker.start(ctx.image("clean", release), f"dry-run-{release}", sudo=True,
                                     user="test", env={"HOME": "/home/test"})
        ctx.clone(container, "test", "/home/test/dev/dotfiles")
        container.exec(f"sudo bash -c \"{LISTING}\" > /tmp/before.txt")
        result = container.exec("cd ~/dev/dotfiles && ./setup.sh --bash --dry-run", check=False, timeout=900)
        if result.returncode != 0:
            raise Failure(f"{release}: setup.sh --bash --dry-run exited {result.returncode}")
        container.exec(f"sudo bash -c \"{LISTING}\" > /tmp/after.txt")
        before = listing(container.exec("cat /tmp/before.txt").stdout)
        after = listing(container.exec("cat /tmp/after.txt").stdout)
        changed = unexpected_changes(before, after)
        if changed:
            raise Failure(f"{release}: the dry run changed the filesystem: " + "; ".join(changed[:5]))
        passed.append(release)
    return f"dry run changed nothing on {', '.join(passed)}"
