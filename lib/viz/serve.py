"""The HTTP server: sign-in, the cross-site checks, containment, the reload script and the gallery.

It reads what it serves and writes only its own state. It never imports anything that publishes or
collects (a page it serves could otherwise reach that code through it).
"""
import datetime
import hashlib
import hmac
import html
import json
import mimetypes
import os
import re
import secrets
import shutil
import socketserver
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler
from pathlib import Path

from .access import CODE_TTL, COOKIE_AGE, HOST_TAG, file_key, token
from .config import IMAGE_SUFFIXES, OPENED, ROOT, TOKEN
from .paths import (
    contained,
    mtime,
    mtime_ns,
    opened_files,
    others_can_write,
    resolve,
    url_parts,
    url_path,
)
from .vscode import diffable, vscode

RELOAD_SCRIPT = """(() => {
  // Reload when this page or an asset it loaded changes. Errors (tunnel down,
  // server restarting, signed out) are skipped, so polling recovers by itself.
  // Polls carry the page's own token instead of the cookie: if the tunnel drops
  // and something else takes the port, an open tab hands it nothing reusable.
  const token = document.currentScript && document.currentScript.dataset.vizPoll;
  let seen = null;
  // Unreachable (tunnel or server down), polls back off to every 30 s, and a
  // banner says so; each poll the tunnel forwards to a dead socket is a line of
  // ssh noise on the client. The first answer clears both.
  let delay = 1000;
  let banner = null;
  const offline = (down) => {
    if (down && !banner) {
      banner = document.createElement('div');
      banner.textContent = 'viz is unreachable, retrying. In WezTerm, Ctrl+Alt+P reconnects.';
      Object.assign(banner.style, {position: 'fixed', bottom: '8px', right: '8px', zIndex: 2147483647,
        padding: '4px 10px', font: '12px system-ui, sans-serif', color: '#fff', background: '#a33',
        borderRadius: '4px', opacity: '0.9', pointerEvents: 'none'});
      document.documentElement.appendChild(banner);
    } else if (!down && banner) {
      banner.remove();
      banner = null;
    }
  };
  const poll = async () => {
    try {
      const r = await fetch('/__viz/version?path=' + encodeURIComponent(location.pathname) + '&poll=' + token,
                            {cache: 'no-store', credentials: 'omit'});
      delay = 1000;
      offline(false);
      if (r.ok) {
        const v = await r.text();
        if (seen !== null && v !== seen) return location.reload();
        seen = v;
      }
    } catch (e) {
      delay = Math.min(delay * 2, 30000);
      offline(true);
    }
    setTimeout(poll, delay);
  };
  // Start once the page's assets have loaded, so the first version covers them.
  if (document.readyState === 'complete') poll(); else addEventListener('load', poll);
  // A /__viz/diff?left=..&right=.. link asks the connected VS Code for a diff.
  // The server takes only same-origin POSTs, so send the link's query as one.
  document.addEventListener('click', async (event) => {
    const link = event.target.closest && event.target.closest('a[href]');
    if (!link) return;
    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || url.pathname !== '/__viz/diff') return;
    event.preventDefault();
    const r = await fetch('/__viz/diff', {method: 'POST', headers: {'X-Viz': '1'}, body: url.searchParams});
    if (!r.ok) alert('viz diff: ' + await r.text());
  });
})();
"""

# Sent with every response. CORP keeps other origins from loading a file as an
# image or script; the referrer stays on this origin, so CDNs never see paths.
COMMON_HEADERS = (
    ('Cache-Control', 'no-store'),
    ('X-Content-Type-Options', 'nosniff'),
    ('Referrer-Policy', 'same-origin'),
    ('Cross-Origin-Resource-Policy', 'same-origin'),
    ('Cross-Origin-Opener-Policy', 'same-origin'),
    ('X-Frame-Options', 'SAMEORIGIN'),
)
# viz's own pages run nothing but the reload script. Served files are the user's
# and agents' pages, trusted like their code: they keep inline scripts and CDNs,
# and are only kept out of other origins' frames.
PAGE_CSP = ("default-src 'none'; script-src 'self'; connect-src 'self'; img-src 'self'; "
            "style-src 'unsafe-inline'; frame-ancestors 'self'; base-uri 'none'; form-action 'none'")
FILE_CSP = "frame-ancestors 'self'"



def tree_version(directory):
    count, newest = 0, mtime_ns(OPENED) if directory == ROOT else 0
    for dirpath, dirnames, filenames in os.walk(directory):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        for name in filenames:
            if not name.startswith('.'):
                count += 1
                newest = max(newest, mtime_ns(os.path.join(dirpath, name)))
    return f'{count}:{newest}'


def reload_tag(poll):
    return f'<script src="/__viz/reload.js" data-viz-poll="{poll}"></script>'


def page(title, body, poll=None):
    script = reload_tag(poll) if poll else ''
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>
  :root {{ color-scheme: light dark; font: 14px system-ui, sans-serif; }}
  body {{ margin: 2rem; }}
  td {{ padding: .3rem .8rem; vertical-align: middle; }}
  td:first-child {{ opacity: .6; white-space: nowrap; }}
  img {{ max-height: 60px; max-width: 160px; background: white; }}
</style></head><body>
{body}
{script}</body></html>"""


def gallery(directory, poll):
    """Every served file under DIRECTORY (under ROOT), newest first, plus opened linked files at the top."""
    files = []
    for dirpath, dirnames, filenames in os.walk(directory):
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]
        files += [Path(dirpath, n) for n in filenames if not n.startswith('.')]
    if directory == ROOT:
        files += opened_files()
    served = [(f, local) for f in files
              if (local := resolve(list(f.relative_to(ROOT).parts))) and local.is_file()]
    served.sort(key=lambda pair: mtime(pair[1]), reverse=True)
    rows = []
    for path, local in served:
        url = url_path(path)
        when = datetime.datetime.fromtimestamp(mtime(local)).strftime('%Y-%m-%d %H:%M')  # noqa: DTZ006
        thumb = f'<img src="{url}" loading="lazy">' if path.suffix.lower() in IMAGE_SUFFIXES else ''
        rel = html.escape(path.relative_to(ROOT).as_posix())
        rows.append(f'<tr><td>{when}</td><td><a href="{url}">{rel}</a></td><td>{thumb}</td></tr>')
    body = '\n'.join(rows) or '<tr><td colspan="3">Nothing yet. Write files with <code>viz path NAME</code>.</td></tr>'
    return page('viz', f'<h1>{html.escape(str(directory))}</h1>\n<table>{body}</table>', poll)


def inject(data, poll):
    """HTML DATA with the reload script before its last </body>."""
    match = None
    for match in re.finditer(rb'</body\s*>', data, re.IGNORECASE):
        pass
    cut = match.start() if match else len(data)
    return data[:cut] + reload_tag(poll).encode() + data[cut:]


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def __init__(self, path):
        self.codes = {}          # single-use sign-in code -> expiry
        self.assets = {}         # page URL parts -> real paths it loaded
        self.browser_seen = None
        self.lock = threading.Lock()
        self._secret = None, b''
        super().__init__(path, Handler)

    def secret(self):
        """The account's secret, reread when the file changes (`viz login --reset`)."""
        key = file_key(TOKEN)
        if key is None or key != self._secret[0]:
            value = token().encode()
            self._secret = file_key(TOKEN), value
        return self._secret[1]

    def mac(self, purpose):
        return hmac.new(self.secret(), purpose.encode(), hashlib.sha256).hexdigest()

    def cookie_value(self, issued):
        """A browser's credential: when it signed in, and an HMAC of that. Not the secret,
        so a leaked cookie cannot mint sign-in codes, and it expires."""
        return f'{issued}.{self.mac(f"browser:{issued}")}'

    def poll_token(self, parts):
        """What a page's reload script shows instead of the cookie: good only for that page's version."""
        return self.mac('poll:' + '/'.join(parts))[:32]

    def mint(self):
        code = secrets.token_urlsafe(16)
        with self.lock:
            now = time.time()
            self.codes = {c: t for c, t in self.codes.items() if t > now}
            self.codes[code] = now + CODE_TTL
        return code

    def redeem(self, code):
        with self.lock:
            return self.codes.pop(code, 0) > time.time()


class Handler(BaseHTTPRequestHandler):
    server_version = 'viz'
    sys_version = ''
    timeout = 30

    def do_GET(self):
        self._handle()

    def do_HEAD(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def _handle(self):
        try:
            self._route()
        except (BrokenPipeError, ConnectionResetError):
            pass
        except (OSError, ValueError):   # odd paths: NUL bytes, names too long
            self._text(400, 'bad request')

    def _route(self):
        url = urllib.parse.urlsplit(self.path)
        self.body = b''
        if self.command == 'POST':
            # Read the body before any answer, so a refusal doesn't break the client's write.
            length = int(self.headers.get('Content-Length') or 0)
            if not 0 <= length <= 65536:
                return self._text(413, 'too large')
            self.body = self.rfile.read(length)
        # The browser's Host names the client end of the tunnel; anything else
        # is a rebinding page under a borrowed name.
        match = re.fullmatch(r'(?:localhost|127\.0\.0\.1|\[::1\])(?::(\d{1,5}))?',
                             self.headers.get('Host', ''), re.IGNORECASE)
        if not match:
            return self._text(421, 'viz answers to localhost and 127.0.0.1 only')
        self.cookie = f'viz-{match.group(1) or 80}-{HOST_TAG}'
        if self.headers.get('Service-Worker'):
            # A worker would outlive the file that registered it, and a sign-out.
            return self._text(403, 'refused: service workers')
        if url.path == '/__viz/login' and self.command == 'GET':
            return self._login(url.query)
        if url.path == '/__viz/version' and self.command == 'GET':
            query = urllib.parse.parse_qs(url.query)
            path = query.get('path', ['/'])[0]
            parts = url_parts(path)
            if parts is not None and hmac.compare_digest(query.get('poll', [''])[0].encode(),
                                                         self.server.poll_token(parts).encode()):
                self.server.browser_seen = time.time()
                return self._text(200, self._version(parts))
        who = self._who()
        if who is None:
            return self._page(403, page('viz: sign in', SIGN_IN))
        if who == 'browser':
            self.server.browser_seen = time.time()
            if not self._fetch_allowed():
                return self._text(403, 'refused: request from another site')
        if self.command == 'POST':
            if url.path == '/__viz/login' and who == 'cli':
                return self._text(200, self.server.mint())
            if url.path == '/__viz/diff':
                return self._diff()
            return self._text(405, 'method not allowed')
        if url.path == '/__viz/ping':
            seen = self.server.browser_seen
            info = {'root': str(ROOT), 'pid': os.getpid(), 'browser': seen and time.time() - seen}
            return self._text(200, json.dumps(info), 'application/json')
        if url.path == '/__viz/version':
            return self._text(200, self._version(url_parts(urllib.parse.parse_qs(url.query).get('path', ['/'])[0])))
        if url.path == '/__viz/reload.js':
            return self._text(200, RELOAD_SCRIPT, 'text/javascript')
        if url.path == '/__viz/diff':
            # Never acts on GET: a link from another site must not open anything.
            return self._text(405, 'POST only: a viz page sends this link as a POST once it has loaded')
        if url.path.startswith('/__viz/'):
            return self._text(404, 'not found')
        parts = url_parts(url.path)
        local = resolve(parts)
        if local is None or not local.exists():
            return self._text(404, 'not found')
        if local.is_dir():
            if not url.path.endswith('/'):
                # Rebuilt from the checked parts, so it can't become //other.host/.
                location = '/' + ''.join(urllib.parse.quote(p) + '/' for p in parts)
                return self._redirect(location + (f'?{url.query}' if url.query else ''))
            index = index_of(parts)
            if index is None:
                if local == ROOT or ROOT in local.parents:
                    return self._page(200, gallery(local, self.server.poll_token(parts)))
                return self._text(404, 'not found: linked directories are not listed')
            local = index
        self._note_asset(parts, local)
        return self._file(local, parts)

    def _who(self):
        """'cli' for the secret as a bearer token, 'browser' for a live sign-in cookie, else None."""
        auth = self.headers.get('Authorization', '')
        if auth.startswith('Bearer ') and hmac.compare_digest(auth[7:].encode(), self.server.secret()):
            return 'cli'
        for pair in self.headers.get('Cookie', '').split(';'):
            name, _, value = pair.strip().partition('=')
            issued = value.partition('.')[0]
            if (name == self.cookie and issued.isdigit() and 0 <= time.time() - int(issued) < COOKIE_AGE
                    and hmac.compare_digest(value.encode(), self.server.cookie_value(int(issued)).encode())):
                return 'browser'
        return None

    def _fetch_allowed(self):
        """Same-origin requests and top-level navigation, by the browser's fetch metadata."""
        site = self.headers.get('Sec-Fetch-Site')
        if site in (None, 'same-origin', 'none'):
            return True
        return (self.command == 'GET' and self.headers.get('Sec-Fetch-Mode') == 'navigate'
                and self.headers.get('Sec-Fetch-Dest') == 'document')

    def _login(self, query):
        query = urllib.parse.parse_qs(query)
        code = query.get('code', [''])[0]
        # Only a path on this origin: not //host, \\host, or a header break.
        land = query.get('next', ['/'])[0]
        if not re.fullmatch(r'/(?![/\\])[\x21-\x7e]*', land):
            land = '/'
        if not self.server.redeem(code):
            return self._page(403, page('viz: sign in', SIGN_IN_AGAIN))
        value = self.server.cookie_value(int(time.time()))
        self.send_response(303)
        self.send_header('Set-Cookie', f'{self.cookie}={value}; Max-Age={COOKIE_AGE}; Path=/; HttpOnly; SameSite=Lax')
        self.send_header('Location', land)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _diff(self):
        # A page asks for this; nothing on another origin may. Origin is exact
        # (scheme, host and port), and the custom header makes a cross-origin
        # fetch need a preflight, which this server never grants.
        if (self.headers.get('Origin') != f'http://{self.headers["Host"]}'
                or self.headers.get('Sec-Fetch-Site', 'same-origin') != 'same-origin'
                or self.headers.get('X-Viz') != '1'):
            return self._text(403, 'refused: diffs are requested by viz pages only')
        query = urllib.parse.parse_qs(self.body.decode(errors='replace'))
        left, right = (diffable(query.get(k, [''])[0]) for k in ('left', 'right'))
        if left is None or right is None:
            return self._text(403, 'refused: two existing files under VIZ_DIFF_ROOTS')
        if not vscode('--reuse-window', '--diff', str(left), str(right)):
            return self._text(409, 'no connected VS Code window')
        return self._text(200, 'opened')

    def _note_asset(self, parts, local):
        """Remember what a page loads, so its version covers its CSS, scripts, images and data."""
        referer = urllib.parse.urlsplit(self.headers.get('Referer', ''))
        page_parts = url_parts(referer.path)
        if referer.netloc != self.headers['Host'] or not page_parts or page_parts == parts:
            return
        with self.server.lock:
            loaded = self.server.assets.setdefault(tuple(page_parts), set())
            if len(loaded) < 1000:
                loaded.add(local)

    def _version(self, parts):
        local = resolve(parts)
        if local is not None and local.is_dir():
            if local == ROOT or ROOT in local.parents:
                return tree_version(local)
            local = index_of(parts)   # a linked directory shows only its index page
        if local is None or not local.is_file():
            return 'missing'
        with self.server.lock:
            assets = sorted(self.server.assets.get(tuple(parts), ()))
        stamp = ':'.join(str(mtime_ns(p)) for p in [local, *assets])
        return hashlib.sha256(stamp.encode()).hexdigest()[:16]

    def _file(self, local, parts):
        ctype = mimetypes.guess_type(local.name)[0] or 'application/octet-stream'
        if ctype.startswith('text/') or ctype in ('application/json', 'image/svg+xml'):
            ctype += '; charset=utf-8'
        try:
            f = open(local, 'rb')  # noqa: SIM115
        except OSError:
            return self._text(404, 'not found')
        with f:
            # Check what was opened, not the path: a symlink swapped in since
            # resolve() must still land inside, and another account's file (or
            # one it can rewrite) is never shown as the user's page.
            info = os.fstat(f.fileno())
            if (contained(os.readlink(f'/proc/self/fd/{f.fileno()}')) is None
                    or info.st_uid != os.getuid() or others_can_write(info)):
                return self._text(404, 'not found')
            if local.suffix.lower() in ('.html', '.htm'):
                return self._send(200, inject(f.read(), self.server.poll_token(parts)), ctype, FILE_CSP)
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(info.st_size))
            self.send_header('Content-Security-Policy', FILE_CSP)
            self.end_headers()
            if self.command != 'HEAD':
                shutil.copyfileobj(f, self.wfile)

    def _send(self, status, data, ctype, csp=PAGE_CSP):
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Content-Security-Policy', csp)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def _text(self, status, text, ctype='text/plain'):
        self._send(status, text.encode(), f'{ctype}; charset=utf-8')

    def _page(self, status, text):
        self._send(status, text.encode(), 'text/html; charset=utf-8')

    def _redirect(self, location):
        self.send_response(301)
        self.send_header('Location', location)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def end_headers(self):
        for name, value in COMMON_HEADERS:
            self.send_header(name, value)
        super().end_headers()

    def log_message(self, *args):
        pass


def index_of(parts):
    """The served index.html (or .htm) of the directory at PARTS, or None."""
    return next((i for i in (resolve(parts + [n]) for n in ('index.html', 'index.htm'))
                 if i and i.is_file()), None)


SIGN_IN = ('<h1>viz: sign in</h1><p>In your ssh session on this machine, run <code>viz open</code> '
           '(through WezTerm), or <code>viz login</code> and open the link it prints. The browser then '
           'stays signed in to this port.</p>')
SIGN_IN_AGAIN = ('<h1>viz: sign in</h1><p>This sign-in link is used or expired. '
                 'Run <code>viz login</code> for a new one.</p>')
