#!/usr/bin/env python3
"""bin/viz: path layout, private socket, sign-in, Host and cross-site checks, containment, reload, lifetime."""
from pathlib import Path
import datetime
import http.client
import os
import re
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
viz = root / 'bin/viz'
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def alive(pid):
    try:
        with open(f'/proc/{pid}/stat') as f:
            return f.read().split(') ')[-1][0] != 'Z'
    except OSError:
        return False


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__('localhost', timeout=5)
        self.unix_path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.unix_path)


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    port = free_port()   # the client port printed in URLs; nothing should listen on it here
    host = f'127.0.0.1:{port}'
    project = tmp / 'project'
    env = dict(os.environ, HOME=str(tmp / 'home'), VIZ_DIR=str(tmp / 'viz'), VIZ_PORT=str(port),
               XDG_STATE_HOME=str(tmp / 'state'), XDG_RUNTIME_DIR=str(tmp / 'run'),
               VIZ_DIFF_ROOTS=str(project))
    env.pop('VSCODE_IPC_HOOK_CLI', None)
    (tmp / 'home').mkdir()
    (tmp / 'run').mkdir(mode=0o700)
    rundir = tmp / 'run' / 'viz'
    sock = rundir / 'http.sock'
    stray = []

    def run(*args, **overrides):
        return subprocess.run([sys.executable, str(viz), *args], env=dict(env, **overrides),
                              capture_output=True, text=True, timeout=20)

    def request(method, path, headers=None, body=None, cookie=None):
        conn = UnixHTTP(str(sock))
        sent = {'Host': host}
        if cookie:
            sent['Cookie'] = f'viz-{port}={cookie}'
        sent.update(headers or {})
        try:
            conn.request(method, path, body=body, headers=sent)
            r = conn.getresponse()
            return r.status, {k.lower(): v for k, v in r.getheaders()}, r.read().decode(errors='replace')
        finally:
            conn.close()

    def server_pid():
        return int((rundir / 'serve.pid').read_text())

    try:
        today = datetime.date.today().isoformat()
        out = run('path', 'chart.html').stdout.strip()
        check(out == str(tmp / 'viz' / today / 'chart.html'), f'path: unexpected {out!r}')
        check((tmp / 'viz' / today).is_dir(), 'path: directory not created')
        check(run('path', '../escape.html').returncode != 0, 'path: accepted ..')

        chart = Path(out)
        chart.write_text('<html><body><p>chart-marker</p></body></html>')
        (tmp / 'secret.txt').write_text('secret')
        (tmp / 'viz' / 'link.txt').symlink_to(tmp / 'secret.txt')
        (tmp / 'viz' / 'escape').symlink_to(tmp, target_is_directory=True)
        (tmp / 'viz' / '.ff-profile').mkdir()
        (tmp / 'viz' / '.ff-profile' / 'prefs.js').write_text('secret')

        result = run('open', str(chart))
        check(result.returncode == 0, f'open: failed {result.stderr}')
        check(f'http://127.0.0.1:{port}/{today}/chart.html' in result.stdout, f'open: URL not printed {result.stdout!r}')
        check('viz status' in result.stdout, f'open: no hint before a browser connects {result.stdout!r}')

        # Only this account can reach the server: a socket in a 0700 directory, no TCP.
        info = os.stat(rundir)
        check(stat.S_IMODE(info.st_mode) == 0o700 and info.st_uid == os.getuid(),
              f'socket: directory mode {oct(info.st_mode)}')
        info = os.lstat(sock)
        check(stat.S_ISSOCK(info.st_mode) and not info.st_mode & 0o077 and info.st_uid == os.getuid(),
              f'socket: mode {oct(info.st_mode)}')
        with socket.socket() as s:
            check(s.connect_ex(('127.0.0.1', port)) != 0, 'socket: something listens on the TCP port')
        token_file = tmp / 'state' / 'viz' / 'token'
        check(stat.S_IMODE(token_file.stat().st_mode) == 0o600, 'token: file not 0600')
        secret = token_file.read_text().strip()

        # No secret, no content: every method and endpoint.
        for method, path in (('GET', '/'), ('GET', f'/{today}/chart.html'), ('HEAD', f'/{today}/chart.html'),
                             ('GET', f'/__viz/version?path=/{today}/chart.html'), ('GET', '/__viz/ping'),
                             ('POST', '/__viz/login')):
            status, _, body = request(method, path)
            check(status == 403 and 'chart-marker' not in body, f'auth: {method} {path} without token gave {status}')
        check(request('GET', '/', cookie='wrong')[0] == 403, 'auth: wrong cookie accepted')
        check(request('GET', '/', headers={'Cookie': f'viz-1={secret}'})[0] == 403,
              "auth: another port's cookie accepted")
        check(request('GET', '/', headers={'Authorization': 'Bearer wrong'})[0] == 403, 'auth: wrong bearer accepted')

        # DNS rebinding: the right secret under a foreign Host is refused.
        for bad in ('evil.example', f'evil.example:{port}', f'localhost.evil.example:{port}', ''):
            status, _, body = request('GET', f'/{today}/chart.html', headers={'Host': bad}, cookie=secret)
            check(status == 421 and 'chart-marker' not in body, f'host: {bad!r} gave {status}')

        # Sign-in: a single-use code from `viz login` becomes the cookie.
        out = run('login').stdout
        match = re.search(rf'http://127\.0\.0\.1:{port}(/__viz/login\?code=[\w-]+)', out)
        check(match is not None and secret not in out, f'login: unexpected output {out!r}')
        if match:
            status, headers, _ = request('GET', match.group(1))
            cookie = headers.get('set-cookie', '')
            check(status == 303 and cookie.startswith(f'viz-{port}={secret};') and 'HttpOnly' in cookie
                  and 'SameSite=Lax' in cookie, f'login: {status} {cookie!r}')
            check(request('GET', match.group(1))[0] == 403, 'login: code worked twice')
        status, headers, _ = request('GET', '/__viz/login?code=guess')
        check(status == 403 and 'set-cookie' not in headers, 'login: guessed code accepted')
        out = run('status').stdout
        check(f'LocalForward 127.0.0.1:{port} {sock}' in out and secret not in out, f'status: {out!r}')

        # Signed in: pages, headers, gallery.
        status, headers, body = request('GET', f'/{today}/chart.html', cookie=secret)
        check(status == 200 and body.index('/__viz/reload.js') < body.index('</body>'),
              'serve: reload script not injected before </body>')
        check(headers.get('x-content-type-options') == 'nosniff'
              and "frame-ancestors 'self'" in headers.get('content-security-policy', '')
              and headers.get('cross-origin-resource-policy') == 'same-origin',
              f'serve: security headers missing {headers}')
        status, _, body = request('GET', '/__viz/reload.js', cookie=secret)
        check(status == 200 and '/__viz/version' in body, 'serve: reload script missing')
        status, headers, body = request('GET', '/', cookie=secret)
        check(status == 200 and 'chart.html' in body, 'serve: gallery missing file')
        check("default-src 'none'" in headers.get('content-security-policy', ''), 'serve: gallery CSP missing')
        check('.ff-profile' not in body and 'link.txt' not in body, 'serve: gallery shows hidden or escaping files')
        status, _, body = request('GET', f'/{today}/', cookie=secret)
        check(status == 200 and 'chart.html' in body, 'serve: no listing of a directory in VIZ_DIR')

        # Containment: traversal, encoded traversal, symlink escapes, hidden paths.
        for path in ('/link.txt', '/escape/secret.txt', '/../secret.txt', '/%2e%2e/secret.txt',
                     '/%2e%2e%2fsecret.txt', '/escape/../../secret.txt', '/.ff-profile/prefs.js',
                     '/%2eff-profile/prefs.js', '/.ff-profile/'):
            for method in ('GET', 'HEAD'):
                status, _, body = request(method, path, cookie=secret)
                check(status == 404 and 'secret' not in body, f'contain: {method} {path} gave {status}')
        check(request('GET', '/__viz/version?path=/.ff-profile/prefs.js', cookie=secret)[2] == 'missing',
              'contain: version of a hidden file')

        # Other sites may navigate to a page but not load, frame or script it.
        page = f'/{today}/chart.html'
        for site, mode, dest, want in (('cross-site', 'no-cors', 'script', 403), ('same-site', 'cors', 'empty', 403),
                                       ('cross-site', 'navigate', 'iframe', 403),
                                       ('cross-site', 'navigate', 'document', 200),
                                       ('same-origin', 'cors', 'empty', 200), ('none', 'navigate', 'document', 200)):
            status = request('GET', page, cookie=secret, headers={
                'Sec-Fetch-Site': site, 'Sec-Fetch-Mode': mode, 'Sec-Fetch-Dest': dest})[0]
            check(status == want, f'fetch metadata: {site}/{mode}/{dest} gave {status}, want {want}')

        # Live reload: the page's version follows the page and the assets it loaded.
        def version(path):
            return request('GET', f'/__viz/version?path={path}', cookie=secret)[2]

        before = version(page)
        check(before == version(page) and before != 'missing', 'reload: version unstable')
        os.utime(chart, ns=(0, 10**18))
        check(version(page) != before, 'reload: version unchanged after the page changed')
        style = chart.with_name('style.css')
        style.write_text('p {}')
        request('GET', f'/{today}/style.css', cookie=secret, headers={'Referer': f'http://{host}{page}'})
        before = version(page)
        os.utime(style, ns=(0, 10**18))
        check(version(page) != before, 'reload: version unchanged after an asset changed')

        # Outside VIZ_DIR: the directory is linked, the gallery lists only what was opened.
        project.mkdir()
        (project / 'plot.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        (project / 'other.html').write_text('<p>other</p>')
        (project / '.env').write_text('secret')
        out = run('open', str(project / 'plot.svg')).stdout
        check(f'http://127.0.0.1:{port}/linked/project/plot.svg' in out, f'open: outside file not linked {out!r}')
        check('/linked/project/plot.svg' in run('open', str(project / 'plot.svg')).stdout
              and len(list((tmp / 'viz' / 'linked').iterdir())) == 1, 'open: relinked the same directory')
        check(request('GET', '/linked/project/other.html', cookie=secret)[0] == 200,
              'serve: sibling in linked directory (relative links)')
        body = request('GET', '/', cookie=secret)[2]
        check('linked/project/plot.svg' in body and 'other.html' not in body,
              'serve: gallery should list opened linked files only')
        check(request('GET', '/linked/project/', cookie=secret)[0] == 404, 'serve: listed a linked directory')
        for path in ('/linked/project/.env', '/linked/project/../secret.txt', '/linked/project/%2e%2e/secret.txt'):
            status, _, body = request('GET', path, cookie=secret)
            check(status == 404 and 'secret' not in body, f'contain: {path} gave {status}')
        (tmp / 'home' / 'report.html').write_text('<p>r</p>')
        check(run('open', str(tmp / 'home' / 'report.html')).returncode != 0, 'open: linked all of home')
        (tmp / 'repo' / '.git').mkdir(parents=True)
        (tmp / 'repo' / 'index.html').write_text('<p>r</p>')
        check(run('open', str(tmp / 'repo' / 'index.html')).returncode != 0, 'open: linked a repository root')
        check('opened' not in run('open', str(project / 'plot.svg'), '--vscode').stdout, 'open: claimed VS Code')
        png = chart.with_name('pic.png')
        png.write_bytes(b'\x89PNG\r\n\x1a\n')
        check(f'/{today}/pic.png' in run('open', str(png)).stdout, 'open: image not served without VS Code')

        # The diff endpoint: same-origin POSTs from a page only.
        form = {'Content-Type': 'application/x-www-form-urlencoded'}
        body = f'left={project}/plot.svg&right={project}/other.html'
        origin = {'Origin': f'http://{host}', 'X-Viz': '1', **form}
        check(request('GET', f'/__viz/diff?{body}', cookie=secret)[0] == 405, 'diff: GET accepted')
        for name, headers in (('no Origin', {'X-Viz': '1', **form}),
                              ('another port', {**origin, 'Origin': 'http://127.0.0.1:1'}),
                              ('no X-Viz', {'Origin': f'http://{host}', **form}),
                              ('cross-site', {**origin, 'Sec-Fetch-Site': 'same-site'})):
            check(request('POST', '/__viz/diff', headers, body, cookie=secret)[0] == 403, f'diff: {name} accepted')
        check(request('POST', '/__viz/diff', origin, body)[0] == 403, 'diff: accepted without cookie')
        outside = f'left={tmp}/secret.txt&right={project}/other.html'
        check(request('POST', '/__viz/diff', origin, outside, cookie=secret)[0] == 403, 'diff: file outside roots')
        check(request('POST', '/__viz/diff', origin, body, cookie=secret)[0] == 409,
              'diff: a valid request should reach VS Code (409 without one)')

        # Lifetime: one server per socket, another VIZ_DIR is refused, stop kills only viz.
        result = run('serve')
        check(result.returncode == 1 and 'already serving' in result.stderr, f'serve: second server {result.stderr!r}')
        result = run('open', str(chart), VIZ_DIR=str(tmp / 'other'))
        check(result.returncode != 0 and 'VIZ_DIR' in result.stderr, f'open: other VIZ_DIR {result.stderr!r}')
        sleeper = subprocess.Popen(['sleep', '30'])
        stray.append(sleeper)
        (tmp / 'state' / 'viz' / 'serve.pid').write_text(str(sleeper.pid))
        run('stop')
        check(sleeper.poll() is None, 'stop: killed a process that is not viz')
        check(not sock.exists(), 'stop: socket left behind')

        # A crashed server leaves its socket; the next command replaces it.
        run('start')
        svg_version = version('/linked/project/plot.svg')
        os.kill(server_pid(), signal.SIGKILL)
        time.sleep(0.2)
        check(sock.exists(), 'restart: test expects the stale socket to remain')
        out = run('open', str(chart)).stdout
        check(f'/{today}/chart.html' in out, f'restart: open after a crash {out!r}')
        check(version('/linked/project/plot.svg') == svg_version, 'restart: version changed across a restart')

        # The server exits once its socket is gone (logout removed the runtime directory).
        pid = server_pid()
        sock.unlink()
        for _ in range(50):
            if not alive(pid):
                break
            time.sleep(0.1)
        check(not alive(pid), 'watch: server outlived its socket')

        # A shared fallback directory someone else could have made is refused unless private.
        (tmp / 'run2' / 'viz').mkdir(parents=True, mode=0o755)
        (tmp / 'run2' / 'viz').chmod(0o755)
        result = run('status', XDG_RUNTIME_DIR=str(tmp / 'run2'))
        check(result.returncode != 0 and 'private' in result.stderr, f'runtime: accepted a 0755 directory {result.stderr!r}')

        # --reset signs every browser out.
        out = run('login', '--reset').stdout
        check(request('GET', '/', cookie=secret)[0] == 403, 'login --reset: old cookie still works')
        check('/__viz/login?code=' in out, 'login --reset: no new link')
    finally:
        run('stop')
        for p in stray:
            p.kill()
            p.wait()

if failures:
    raise SystemExit('\n'.join(failures))
print('viz: ok')
