"""The VS Code bridge: a connected Remote-SSH window opens files as tabs and shows diffs."""
import glob
import os
import socket
import subprocess
from pathlib import Path

from .config import DIFF_ROOTS
from .paths import mtime


def _socket_live(path):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(0.5)
    try:
        s.connect(path)
        return True
    except OSError:
        return False
    finally:
        s.close()


def _own_socket_live(path):
    """A live socket of this account (VS Code falls back to /tmp, where anyone can make one)."""
    try:
        return os.stat(path).st_uid == os.getuid() and _socket_live(path)
    except OSError:
        return False


def vscode_socket():
    """Newest IPC socket with a window behind it; most on disk are stale."""
    current = os.environ.get('VSCODE_IPC_HOOK_CLI')
    if current and _own_socket_live(current):
        return current
    runtime = os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{os.getuid()}'
    candidates = glob.glob(os.path.join(runtime, 'vscode-ipc-*.sock'))
    for path in sorted(candidates, key=mtime, reverse=True):
        if _own_socket_live(path):
            return path
    return None


def vscode_cli():
    """Remote CLI of a running VS Code server, else the newest installed one."""
    home = os.path.expanduser('~')
    clis = glob.glob(f'{home}/.vscode-server/cli/servers/*/server/bin/remote-cli/code')
    clis += glob.glob(f'{home}/.vscode-server/bin/*/bin/remote-cli/code')
    if not clis:
        return None
    running = set()
    for cmdline in glob.glob('/proc/[0-9]*/cmdline'):
        try:
            with open(cmdline, 'rb') as f:
                running.add(f.read().split(b'\0')[0].decode(errors='replace'))
        except OSError:
            continue
    for cli in clis:
        server = cli[:-len('bin/remote-cli/code')]
        if any(exe.startswith(server) for exe in running):
            return cli
    return max(clis, key=mtime)


def vscode(*args):
    """Run the remote CLI against a live window; False when none is connected."""
    sock, cli = vscode_socket(), vscode_cli()
    if not sock or not cli:
        return False
    env = dict(os.environ, VSCODE_IPC_HOOK_CLI=sock)
    return subprocess.run([cli, *args], env=env, stdout=subprocess.DEVNULL, check=False).returncode == 0


def diffable(path):
    """``path`` resolved, if it is an existing, unhidden file under DIFF_ROOTS; else None."""
    try:
        local = Path(os.path.realpath(path))
        if not local.is_file():
            return None
    except (OSError, ValueError):   # NUL bytes, names too long
        return None
    for root in DIFF_ROOTS:
        if root in local.parents and not any(p.startswith('.') for p in local.relative_to(root).parts):
            return local
    return None
