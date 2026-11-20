"""Show visualizations written on this machine in the browser of the ssh client.

Agents running in tmux over ssh cannot draw on the client screen. viz serves
VIZ_DIR over HTTP on a Unix socket in this account's private runtime directory,
which no other account can open, and the client forwards a local port to it:

    ssh -L 127.0.0.1:PORT:/run/user/UID/viz/http.sock HOST

WezTerm's Ctrl+Alt+P opens that forward (through `forwards`, which runs `viz
forward`), and `viz open` in your terminal then opens a page in that browser,
signed in; `viz status` prints the forward for this machine. HTML, SVG and PDF are served
(and images, when no VS Code window is connected); a page reloads when it or an
asset it loaded changes.

Anything on the client can open the forwarded port, so the server also wants a
secret: a browser signs in with the single-use link `viz login` prints and
keeps a cookie for 30 days (an HMAC of the account's secret, never the secret).
Every request needs that cookie and a localhost Host header (against DNS
rebinding), and only top-level navigation may come from another site: other
origins cannot embed, frame or script the pages. Reload polls carry a per-page
token instead of the cookie. Hidden paths, anything outside VIZ_DIR and its
linked directories, and files another account owns or can write are never
served.

A browser file outside VIZ_DIR is served through a link to its directory in
VIZ_DIR/linked, so relative links and reload on rebuild keep working. Home, the
directories above it, the temp root, repository roots, hidden directories and
directories other accounts can write are never linked.

With a VS Code Remote-SSH window connected, other files (PNG, notebooks,
Markdown with mermaid, ...) open in it as tabs, and `viz diff` or a page (a link
to ``/__viz/diff?left=PATH&right=PATH``, which viz turns into a same-origin POST)
opens a side-by-side diff of two existing files under VIZ_DIFF_ROOTS.

A page is drafted in a folder `viz path` makes, with a page.toml manifest
(title, summary, where it came from), and published with `viz publish PAGE
--to TARGET`; `viz targets` lists the targets, who sees each, and its rules.
Publishing is a command only: the server never publishes. A live page
(`viz publish --to live`) stays at VIZ_DIR/live/NAME/ and is rewritten by its
collector, a command `viz collect` runs every interval (the viz-collect user
service runs it); `viz status` shows each one's last run.

Environment:
    VIZ_DIR    served root and home of `viz path` output (default ~/viz)
    VIZ_PORT   client port in printed URLs and forwards
               (default 20000 + uid % 10000, stable per account)
    VIZ_DIFF_ROOTS  colon-separated directories whose files a page may diff
               (default ~/projects:~/ref)
    VIZ_STATE  the account's secret, sign-ins and logs (default ~/.local/state/viz;
               XDG_STATE_HOME is ignored, so every shell reaches the one server)
    VIZ_CONFIG config.toml and the publishing targets in targets.d/
               (default ~/.config/viz; XDG_CONFIG_HOME is ignored too)
"""
import argparse
import base64
import fcntl
import os
import signal
import socket
import stat
import subprocess
import sys
import threading
import urllib.parse
from pathlib import Path

from . import bundle, collect, manifest, targets
from .access import (
    CODE_TTL,
    ensure_server,
    inode_of,
    login_path,
    new_token,
    runtime_dir,
    server_pid,
    server_state,
    socket_path,
    stop,
    token,
    watch,
)
from .config import (
    BROWSER_SUFFIXES,
    IMAGE_SUFFIXES,
    PORT,
    REPO,
    ROOT,
    STATE,
    URL_HOST,
    die,
)
from .paths import link_dir, link_refusal, remember, url_for
from .serve import Server
from .vscode import vscode, vscode_cli, vscode_socket


def connect_hint(info):
    if info.get('browser') is None:
        print('no browser has reached viz yet: Ctrl+Alt+P in WezTerm forwards the port, and `viz open` '
              'in your terminal opens it signed in (or `viz status` shows the ssh forward, `viz login` signs in)')


def cmd_path(args):
    """A draft folder ROOT/DATE/FOLDER/ with a page.toml stub; prints the path NAME asked for.

    NAME's first component names the folder. An html file at the top becomes the folder's index.html, any
    other file keeps its name, and a NAME without a suffix is the folder itself.
    """
    name = Path(args.name)
    if name.is_absolute() or '..' in name.parts or not name.parts:
        die('NAME must be a relative path without ..')
    day = manifest.today()
    if len(name.parts) == 1 and name.suffix:
        folder = ROOT / day.isoformat() / name.stem
        entry = 'index.html' if manifest.format_of(name) == 'html' else name.name
        path = folder / entry
    else:
        folder = ROOT / day.isoformat() / name.parts[0]
        entry = Path(*name.parts[1:]).as_posix() if len(name.parts) > 1 else None
        path = folder / entry if entry else folder
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        folder.mkdir(exist_ok=True)
    except (FileExistsError, NotADirectoryError):
        die(f'{folder} exists and is not a directory; pick another NAME')
    source = manifest.provenance(Path.cwd())
    text = manifest.stub(args.title or folder.name, entry=entry, kind=args.kind,
                         project=args.project or manifest.project_name(source), source=source, day=day)
    if not manifest.create(folder / manifest.NAME, text) and (args.title or args.kind or args.project):
        print(f'viz: {folder / manifest.NAME} exists and is left as it is', file=sys.stderr)
    print(path)


def cmd_open(args):
    info = None
    # Run in a terminal (yours, not an agent's), pages open in the client's
    # browser too. Everything else only prints the URL.
    show = sys.stdout.isatty()
    shown = False
    for arg in args.files or [str(ROOT)]:
        path = Path(arg).expanduser().resolve()
        if not path.exists():
            die(f'no such file: {arg}')
        suffix = path.suffix.lower()
        browser = args.browser or (not args.vscode and (path.is_dir() or suffix in BROWSER_SUFFIXES))
        if not browser:
            if vscode('--reuse-window', str(path)):
                print(f'opened in VS Code: {path}')
                continue
            if args.vscode or suffix not in IMAGE_SUFFIXES:
                print(f'no connected VS Code window; open {path} yourself')
                continue
            # Without VS Code, the browser shows images too.
        if path != ROOT and ROOT not in path.parents:
            directory = path if path.is_dir() else path.parent
            refusal = link_refusal(directory)
            if refusal:
                die(f'refusing to serve all of {directory}: {refusal}; write the file under a subdirectory '
                    'of your own, or to `viz path`')
            if path.is_dir() and not any((path / n).is_file() for n in ('index.html', 'index.htm')):
                die(f'{path} has no index.html; open a file in it (linked directories are not listed)')
            link = link_dir(directory)
            print(f'serving {directory} as {link}')
            path = link if path.is_dir() else link / path.name
            if not path.is_dir():
                remember(path)
        info = ensure_server()
        url = url_for(path)
        print(url)
        if show:
            wezterm_open(urllib.parse.urlsplit(url).path)
            shown = True
    if shown and not forwarded():
        print('the ports are not forwarded: press Ctrl+Alt+P in WezTerm, then viz open again')
    elif info and not shown:
        connect_hint(info)


def cmd_diff(args):
    left, right = Path(args.left).expanduser().resolve(), Path(args.right).expanduser().resolve()
    for path in (left, right):
        if not path.is_file():
            die(f'no such file: {path}')
    if vscode('--reuse-window', '--diff', str(left), str(right)):
        print(f'opened in VS Code: {left} <> {right}')
    else:
        print(f'no connected VS Code window; run: code --diff {left} {right}')



def login_url():
    return f'http://{URL_HOST}:{PORT}' + login_path()


def wezterm_open(land):
    """Ask the WezTerm this terminal runs in to open LAND, signed in, in its browser.

    A user variable (OSC 1337 SetUserVar), wrapped for tmux's passthrough. WezTerm
    opens only 127.0.0.1 on a port its Ctrl+Alt+P tunnel forwards, and builds the
    URL itself (configs/wezterm.lua). The sign-in code goes to the terminal, never
    to the screen or the output.
    """
    value = base64.b64encode(f'{PORT} {login_path(land)}'.encode()).decode()
    sequence = f'\033]1337;SetUserVar=viz_open={value}\007'
    if os.environ.get('TMUX'):
        sequence = '\033Ptmux;' + sequence.replace('\033', '\033\033') + '\033\\'
    sys.stdout.write(sequence)
    sys.stdout.flush()


def forwarded():
    """Whether a WezTerm tunnel carries this machine's ports (bin/forwards status)."""
    forwards = REPO / 'bin' / 'forwards'
    return subprocess.run([str(forwards), 'status'], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, check=False).returncode == 0


def cmd_login(args):
    if args.reset:
        new_token(replace=True)   # the server rereads it: every cookie stops working
    ensure_server()
    print(login_url())
    print(f'single use within {CODE_TTL // 60} minutes; the browser then stays signed in to port {PORT}')


def cmd_forward(args):
    """One `forwards` line: the client port, this socket, and the index."""
    ensure_server()
    print(f'viz\t{PORT}\t{socket_path()}\thttp://{URL_HOST}:{PORT}/')


def cmd_start(args):
    info = ensure_server()
    print(f'http://{URL_HOST}:{PORT}/')
    connect_hint(info)


def cmd_serve(args):
    ROOT.mkdir(parents=True, exist_ok=True)
    path = socket_path()
    os.chdir('/')
    # Held until exit: one server per socket, and `viz stop` can tell a live
    # server from a stale PID file. Whoever holds it owns the socket path.
    lock = open(path.parent / 'serve.lock', 'a')  # noqa: SIM115
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        die(f'already serving on {path}')
    if os.path.lexists(path):
        if not stat.S_ISSOCK(os.lstat(path).st_mode):
            die(f'{path} exists and is not a socket; remove it')
        path.unlink()   # left by a server that died
    token()
    old = os.umask(0o177)   # the socket is 0600 from the moment it exists
    try:
        server = Server(str(path))
    finally:
        os.umask(old)
    inode = inode_of(path)
    pidfile = path.parent / 'serve.pid'
    pidfile.write_text(str(os.getpid()))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    threading.Thread(target=watch, args=(server, path, inode), daemon=True).start()
    print(f'serving {ROOT} on {path}', flush=True)
    try:
        server.serve_forever()
    finally:
        if inode_of(path) == inode:
            path.unlink()
        if server_pid(pidfile) == os.getpid():
            pidfile.unlink()


def cmd_stop(args):
    stopped = False
    # The second is the 127.0.0.1 TCP server of viz before the socket.
    rundir = runtime_dir()
    for pidfile, lockfile, what in ((rundir / 'serve.pid', rundir / 'serve.lock', 'server'),
                                    (STATE / 'serve.pid', None, 'old TCP server')):
        pid = stop(pidfile, lockfile)
        if pid:
            print(f'stopped {what} (pid {pid})')
            stopped = True
    if not stopped:
        print('server not running')


def cmd_status(args):
    path = socket_path()
    state, info = server_state()
    print(f'dir:      {ROOT}')
    if state == 'ours':
        seen = info['browser']
        print(f'server:   running (pid {info["pid"]}) on {path}')
        print('browser:  ' + ('no request yet' if seen is None else f'last request {seen:.0f}s ago'))
    elif state == 'other':
        print(f'server:   {path} answers for another VIZ_DIR or secret; run viz stop')
    else:
        print(f'server:   stopped (viz start, viz open or viz login starts it on {path})')
    print(f'url:      http://{URL_HOST}:{PORT}/')
    print('forward:  Ctrl+Alt+P in WezTerm (then `viz open` opens pages, signed in), or by hand:')
    print(f'          ssh -o ExitOnForwardFailure=yes -L {URL_HOST}:{PORT}:{path} {socket.gethostname()}')
    print(f'          or, in the client\'s ssh config: LocalForward {URL_HOST}:{PORT} {path}')
    print('sign in:  run `viz login` yourself and open its single-use link')
    legacy = server_pid(STATE / 'serve.pid')
    if legacy:
        print(f'old:      a TCP server from an earlier viz still runs (pid {legacy}); viz stop ends it')
    print('targets:  ' + targets.status_line())
    print('collect:  ' + '\n          '.join(collect.status_lines()))
    sock, cli = vscode_socket(), vscode_cli()
    print('vscode:   ' + ('connected' if sock and cli else
                          'no VS Code server installed' if not cli else 'no connected window'))



def main():
    parser = argparse.ArgumentParser(
        prog='viz', description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('path', help="make today's draft folder for NAME, with its page.toml, and print the path")
    p.add_argument('name', help='report (the folder), report.html (its index.html), report.pdf, report/data.json')
    p.add_argument('--title', help='the title in a new page.toml (default: the folder name)')
    p.add_argument('--kind', help='the form: answer, explainer, report, dashboard, ...')
    p.add_argument('--project', help='the project (default: from config.toml, else the repository name)')
    p.set_defaults(func=cmd_path)
    p = sub.add_parser('open', help='print the browser URL of files (the index without any), open them in '
                                    "the client's browser from a terminal in WezTerm, or in the connected VS Code")
    target = p.add_mutually_exclusive_group()
    target.add_argument('--browser', action='store_true', help='always serve to the browser')
    target.add_argument('--vscode', action='store_true', help='always open as a VS Code tab')
    p.add_argument('files', nargs='*')
    p.set_defaults(func=cmd_open)
    p = sub.add_parser('diff', help='open a side-by-side diff of two files in the connected VS Code')
    p.add_argument('left')
    p.add_argument('right')
    p.set_defaults(func=cmd_diff)
    p = sub.add_parser('login', help='print a single-use link that signs a browser in')
    p.add_argument('--reset', action='store_true', help='new secret first: signs every browser out')
    p.set_defaults(func=cmd_login)
    sub.add_parser('forward', help='print the forward line `forwards` collects for WezTerm').set_defaults(
        func=cmd_forward)
    sub.add_parser('start', help='start the background server').set_defaults(func=cmd_start)
    sub.add_parser('serve', help='run the server in the foreground').set_defaults(func=cmd_serve)
    sub.add_parser('stop', help='stop the background server').set_defaults(func=cmd_stop)
    sub.add_parser('status', help='show the server, how to forward to it, the targets, the collectors and VS Code'
                   ).set_defaults(func=cmd_status)
    sub.add_parser('collect', help="run the live pages' collectors in the foreground (what viz-collect.service "
                                   'runs)').set_defaults(func=collect.cmd_collect)
    p = sub.add_parser('bundle', help="write a page's portable form and list what keeps it from being portable")
    p.add_argument('page', help='a page folder, its page.toml, or a file')
    p.add_argument('--format', metavar='FMT', help="the form to make (default: the page's own; pdf exports html)")
    p.add_argument('--out', metavar='DIR', help='where (default: $VIZ_STATE/bundles/NAME, replaced each run)')
    p.set_defaults(func=bundle.cmd_bundle)
    p = sub.add_parser('look', help='screenshots of a page in light and dark, and what broke (scripts, loads, '
                                    'network, sideways scroll)')
    p.add_argument('page', help='a page folder, its page.toml, or an html or svg file')
    p.add_argument('--portable', action='store_true', help='bundle it first and look at the bundle, offline: '
                                                           'what a teammate will see')
    p.add_argument('--theme', choices=('light', 'dark', 'both'), help='default both')
    p.add_argument('--width', type=int, help='viewport width (default 1280)')
    p.add_argument('--phone', action='store_true', help='also at 390 px wide, light only')
    p.add_argument('--full', action='store_true', help='the whole page, not the first screen (cut at 6000 px)')
    p.add_argument('--selector', metavar='CSS', help='only the first element matching CSS')
    p.add_argument('--ready', metavar='CSS', help='wait up to 20 s for an element matching CSS')
    p.add_argument('--js', metavar='CODE', help='run CODE after load, before the shot')
    p.add_argument('--wait', type=int, metavar='MS', help='extra wait after load (default 300)')
    p.set_defaults(func=bundle.cmd_look)
    p = sub.add_parser('targets', help='list where pages can be published, for whom, and under which rules')
    p.add_argument('name', nargs='?', help='one target, with its rules in full')
    p.add_argument('--json', action='store_true', help='as JSON, for tools')
    p.set_defaults(func=targets.cmd_targets)
    p = sub.add_parser('publish', help='publish a page to a target (run viz targets first: who sees it, the rules)')
    p.add_argument('page', nargs='?', help="a page folder, its page.toml, or a file (a loose file's manifest is "
                                           'FILE.page.toml)')
    p.add_argument('--to', required=True, metavar='TARGET', help='where: preview, file, live, or a configured target')
    p.add_argument('--as', dest='as_name', metavar='SLUG',
                   help='the name in its place (default: the folder name, or where it was published last)')
    p.add_argument('--format', metavar='FMT', help="publish as FMT, exported if it is not the page's own")
    p.add_argument('--set', action='append', metavar='KEY=VALUE', help='a field of the published manifest')
    p.add_argument('-m', '--message', help="a git target's commit message")
    p.add_argument('--out', metavar='PATH', help='file target: the folder (or FILE.pdf) to write')
    p.add_argument('--dry-run', action='store_true', help='print the place, URL, files and manifest; change nothing')
    p.add_argument('--push', action='store_true', help="a git target's pending commits: push them (at a terminal)")
    p.add_argument('--run', metavar='COMMAND', help='live target: the collector, run by sh -c every interval; '
                                                   'it writes the page at $VIZ_OUT')
    p.add_argument('--every', metavar='INTERVAL', help='live target: how often the collector runs (30s, 5m, 1h)')
    p.add_argument('--cwd', metavar='DIR', help='live target: where the collector runs (default: here)')
    p.add_argument('--title', help='live target without a page: the title (default: the --as NAME)')
    p.add_argument('--summary', help='live target without a page: what the page shows, in a sentence or two')
    p.set_defaults(func=targets.cmd_publish)
    args = parser.parse_args()
    args.func(args)

