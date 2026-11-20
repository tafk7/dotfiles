"""The account's secret, the private socket, and the background server's lifetime."""
import fcntl
import hashlib
import http.client
import json
import os
import secrets
import signal
import socket
import stat
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

from .config import ENTRY, ROOT, STATE, TOKEN, die

CODE_TTL = 600               # seconds a `viz login` link stays valid
COOKIE_AGE = 30 * 86400      # a sign-in lasts this long; the server enforces it
# Browsers send 127.0.0.1's cookies to every port, so the cookie is named after
# the port and this host: forwards to two hosts keep separate sign-ins.
HOST_TAG = hashlib.sha256(socket.gethostname().encode()).hexdigest()[:6]


def file_key(path):
    try:
        info = os.stat(path)
        return info.st_ino, info.st_mtime_ns, info.st_size
    except OSError:
        return None


def runtime_dir():
    """This account's private socket directory, created 0700 on first use.

    $XDG_RUNTIME_DIR/viz, or /run/user/UID/viz; else STATE/run, not /tmp, where
    another account could create the directory first. Ownership and mode are
    checked either way.
    """
    uid = os.getuid()
    for base in (os.environ.get('XDG_RUNTIME_DIR'), f'/run/user/{uid}'):
        if base and os.path.isdir(base) and os.stat(base).st_uid == uid:
            path = Path(base) / 'viz'
            break
    else:
        STATE.mkdir(parents=True, exist_ok=True)
        path = STATE / 'run'
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = os.lstat(path)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != uid or info.st_mode & 0o077:
        die(f'{path} is not a directory private to this account; remove it and retry')
    return path


def socket_path():
    path = runtime_dir() / 'http.sock'
    if len(os.fsencode(path)) > 107:
        die(f'socket path too long for a Unix socket: {path}')
    return path


def token():
    """The account's secret, created on first use; a truncated one is replaced, never trusted."""
    try:
        if TOKEN.stat().st_mode & 0o077:
            TOKEN.chmod(0o600)
        value = TOKEN.read_text().strip()
    except FileNotFoundError:
        return new_token(replace=False)
    return value if len(value) >= 32 else new_token(replace=True)


def new_token(replace):
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = STATE / f'.token.{os.getpid()}'
    with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        f.write(secrets.token_urlsafe(32))
        f.flush()
        os.fsync(f.fileno())   # never a zero-length secret after a crash
    try:
        if replace:
            tmp.replace(TOKEN)
        else:
            os.link(tmp, TOKEN)   # refuses to replace: a concurrent first use wins
    except FileExistsError:
        pass
    finally:
        tmp.unlink(missing_ok=True)
    return TOKEN.read_text().strip()


class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__('localhost', timeout=2)
        self.unix_path = str(path)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.unix_path)


def ask(method, path):
    """(status, body) from the server on our socket; None when nothing answers."""
    conn = _UnixHTTP(socket_path())
    try:
        conn.request(method, path, headers={'Authorization': f'Bearer {token()}'})
        r = conn.getresponse()
        return r.status, r.read().decode()
    except (OSError, http.client.HTTPException):
        return None
    finally:
        conn.close()


def server_state():
    """('ours', ping info), ('other', None) for a server with another VIZ_DIR or secret, or ('down', None)."""
    reply = ask('GET', '/__viz/ping')
    if reply is None:
        return 'down', None
    status, body = reply
    if status != 200:
        return 'other', None
    info = json.loads(body)
    return ('ours' if info.get('root') == str(ROOT) else 'other'), info


def ensure_server():
    """Ping info of the running server, started in the background if need be."""
    state, info = server_state()
    if state == 'other':
        die('the running server has another VIZ_DIR or secret; run viz stop')
    if state == 'ours':
        return info
    token()   # before the server reads it
    STATE.mkdir(parents=True, exist_ok=True)
    log_path = STATE / 'serve.log'
    with open(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600), 'ab') as log:
        os.fchmod(log.fileno(), 0o600)
        subprocess.Popen([sys.executable, str(ENTRY), 'serve'],
                         stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                         start_new_session=True)
    for _ in range(30):
        time.sleep(0.1)
        state, info = server_state()
        if state == 'ours':
            return info
    die(f'server did not start; see {STATE / "serve.log"}')


def inode_of(path):
    try:
        return os.stat(path).st_ino
    except OSError:
        return None


def watch(server, path, inode):
    """Stop once our socket is gone or replaced (logout removed the runtime directory, say)."""
    while inode_of(path) == inode:
        time.sleep(2)
    server.shutdown()


def server_pid(pidfile):
    """The PID in PIDFILE if that process is still this account's viz server; else None."""
    try:
        pid = int(pidfile.read_text())
        owner = os.stat(f'/proc/{pid}').st_uid
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            argv = f.read().split(b'\0')
    except (OSError, ValueError):
        return None
    if owner != os.getuid() or b'serve' not in argv or not any(os.path.basename(a) == b'viz' for a in argv):
        return None
    return pid


def lock_held(lockfile):
    """True while a server holds LOCKFILE, which it does for its whole life."""
    try:
        with open(lockfile, 'a') as f:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
    except BlockingIOError:
        return True


def stop(pidfile, lockfile=None):
    """Stop the server in PIDFILE and wait for it; its PID, or None if none ran.
    With LOCKFILE, only while a server holds it: a stale PID may name another process."""
    pid = server_pid(pidfile)
    if pid is None or (lockfile and not lock_held(lockfile)):
        return None
    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not os.path.exists(f'/proc/{pid}'):
            break
        time.sleep(0.1)
    return pid


def login_path(land='/'):
    """A single-use sign-in path on this origin that lands on LAND."""
    reply = ask('POST', '/__viz/login')
    if not reply or reply[0] != 200:
        die('the server gave no sign-in code; see `viz status`')
    path = f'/__viz/login?code={reply[1]}'
    return path if land == '/' else path + '&next=' + urllib.parse.quote(land, safe='')
