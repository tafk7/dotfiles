#!/usr/bin/env python3
"""bin/viz: path layout, containment, linked directories, reload injection, no-VS Code fallback."""
from pathlib import Path
import datetime
import os
import socket
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

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


def get(port, path):
    try:
        with urllib.request.urlopen(f'http://127.0.0.1:{port}{path}', timeout=2) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, ''


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    port = free_port()
    env = dict(os.environ, HOME=str(tmp / 'home'), VIZ_DIR=str(tmp / 'viz'), VIZ_PORT=str(port),
               XDG_STATE_HOME=str(tmp / 'state'), XDG_RUNTIME_DIR=str(tmp / 'run'))
    env.pop('VSCODE_IPC_HOOK_CLI', None)
    (tmp / 'home').mkdir()
    (tmp / 'run').mkdir()

    def run(*args):
        return subprocess.run([sys.executable, str(viz), *args], env=env,
                              capture_output=True, text=True, timeout=20)

    try:
        today = datetime.date.today().isoformat()
        out = run('path', 'chart.html').stdout.strip()
        check(out == str(tmp / 'viz' / today / 'chart.html'), f'path: unexpected {out!r}')
        check((tmp / 'viz' / today).is_dir(), 'path: directory not created')
        check(run('path', '../escape.html').returncode != 0, 'path: accepted ..')

        Path(out).write_text('<html><body><p>hi</p></body></html>')
        (tmp / 'secret.txt').write_text('secret')
        (tmp / 'viz' / 'link.txt').symlink_to(tmp / 'secret.txt')

        result = run('open', out)
        check(result.returncode == 0, f'open: failed {result.stderr}')
        check('no connected VS Code window' in result.stdout, f'open: no fallback message {result.stdout!r}')
        check(f'http://localhost:{port}/{today}/chart.html' in result.stdout, 'open: URL not printed')

        status, body = get(port, f'/{today}/chart.html')
        check(status == 200 and body.index('/__viz/version') < body.index('</body>'),
              'serve: reload script not injected before </body>')
        status, body = get(port, '/')
        check(status == 200 and 'chart.html' in body, 'serve: gallery missing file')
        check(get(port, '/link.txt')[0] == 404, 'serve: followed symlink outside root')
        check(get(port, '/../secret.txt')[1] != 'secret', 'serve: traversal outside root')
        before = get(port, f'/__viz/version?path=/{today}/chart.html')[1]
        os.utime(out, ns=(0, 10**18))
        check(get(port, f'/__viz/version?path=/{today}/chart.html')[1] != before, 'serve: version unchanged')

        project = tmp / 'project'
        project.mkdir()
        (project / 'plot.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        (project / 'other.html').write_text('<p>other</p>')
        out = run('open', str(project / 'plot.svg')).stdout
        check(f'http://localhost:{port}/linked/project/plot.svg' in out, f'open: outside file not linked {out!r}')
        check(f'/linked/project/plot.svg' in run('open', str(project / 'plot.svg')).stdout
              and len(list((tmp / 'viz' / 'linked').iterdir())) == 1, 'open: relinked the same directory')
        check(get(port, '/linked/project/other.html')[0] == 200, 'serve: sibling in linked directory')
        check('linked/project/other.html' in get(port, '/')[1], 'serve: gallery missing linked file')
        check(get(port, '/linked/project/../secret.txt')[1] != 'secret', 'serve: escaped linked directory')
        check('opened' not in run('open', str(project / 'plot.svg'), '--vscode').stdout, 'open: claimed VS Code')
    finally:
        run('stop')

if failures:
    raise SystemExit('\n'.join(failures))
print('viz: ok')
