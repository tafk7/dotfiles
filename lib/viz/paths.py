"""What is served: containment under VIZ_DIR and its linked directories, links, and URL paths."""
import os
import tempfile
import urllib.parse
from pathlib import Path

from .config import LINKED, OPENED, PORT, ROOT, STATE, URL_HOST


def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0


def mtime_ns(path):
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return -1


def url_parts(path):
    """Components of a URL path; None if any is hidden ('.', '..', dotfiles)."""
    parts = [p for p in urllib.parse.unquote(path).split('/') if p]
    if any(p.startswith('.') or '\0' in p for p in parts):
        return None
    return parts


def others_can_write(info):
    """True if another account could replace what INFO describes: world-writable,
    or group-writable by a group other than this account's own."""
    return bool(info.st_mode & 0o002 or (info.st_mode & 0o020 and info.st_gid != os.getgid()))


def link_refusal(directory):
    """Why DIRECTORY may not be linked whole, or None. Home and above it, the temp
    root and repository roots are too broad; a hidden directory or one another
    account owns or can write into could hand the browser someone else's page."""
    home = Path.home().resolve()
    if directory == home or directory in home.parents:
        return 'it is your home or above it'
    if directory == Path(tempfile.gettempdir()).resolve():
        return 'it is the temp directory'
    if (directory / '.git').exists():
        return 'it is a repository root'
    if any(p.startswith('.') for p in directory.parts):
        return 'it is hidden'
    try:
        info = os.stat(directory)
    except OSError:
        return 'it is unreadable'
    if info.st_uid != os.getuid() or others_can_write(info):
        return 'another account owns it or can write to it'
    return None


def linked_dirs():
    return [p for p in LINKED.iterdir() if p.is_symlink() and p.is_dir()] if LINKED.is_dir() else []


def served_roots():
    roots = [str(ROOT)]
    for link in linked_dirs():
        target = os.path.realpath(link)
        if link_refusal(Path(target)) is None:
            roots.append(target)
    return roots


def contained(local):
    """LOCAL (a real path) as a Path if it is served; a hidden component below its
    root counts even when a symlink leads there. Else None."""
    for root in served_roots():
        if local == root or local.startswith(root + os.sep):
            if any(p.startswith('.') for p in local[len(root):].split(os.sep)):
                return None
            return Path(local)
    return None


def resolve(parts):
    """Real path of the served file or directory at URL PARTS; None if it is not served."""
    if parts is None:
        return None
    return contained(os.path.realpath(ROOT.joinpath(*parts)))


def url_path(path):
    """URL path of PATH, a path under ROOT (linked files through their link)."""
    rel = path.relative_to(ROOT)
    return '/' + urllib.parse.quote(rel.as_posix()) if rel.parts else ''


def opened_files():
    try:
        return [ROOT / line for line in OPENED.read_text().splitlines() if line]
    except FileNotFoundError:
        return []


def remember(path):
    """Note a file opened from a linked directory, so the gallery lists it but not its siblings."""
    rel = path.relative_to(ROOT).as_posix()
    if ROOT / rel not in opened_files():
        STATE.mkdir(parents=True, exist_ok=True)
        with open(OPENED, 'a') as f:
            f.write(rel + '\n')


def url_for(path):
    return f'http://{URL_HOST}:{PORT}' + url_path(path) + ('/' if path.is_dir() else '')


def link_dir(directory):
    """The VIZ_DIR/linked entry for DIRECTORY, created on first use."""
    for link in linked_dirs():
        if link.resolve() == directory:
            return link
    LINKED.mkdir(parents=True, exist_ok=True)
    name, n = directory.name or 'root', 1
    link = LINKED / name
    while link.exists() or link.is_symlink():
        n += 1
        link = LINKED / f'{name}-{n}'
    link.symlink_to(directory, target_is_directory=True)
    return link
