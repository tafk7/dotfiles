"""html: the portable form is one folder that loads nothing from outside itself.

1. What a browser reads is copied from the draft folder (formats.copy_page).
2. Google Fonts a page links or @imports are downloaded into fonts/, their CSS rewritten to fonts/fonts.css,
   and the page pointed at it; fonts/MANIFEST.json records each file's source URL and sha256.
3. A script or stylesheet from a CDN whose URL names an exact version (d3@7.9.0, /7.9.0/) is downloaded into
   vendor/PACKAGE@VERSION/ and recorded in vendor/MANIFEST.json. A range or tag (@7, @latest) fails the bundle.
4. Anything else loaded from outside (an API fetch, an unpinned script, an image URL) fails the bundle, unless
   the target allows the network.
5. Relative links must resolve inside the bundle.
"""
import html
import json
import posixpath
import re
import tempfile
import urllib.parse
from pathlib import Path

from .. import fetch
from . import Problem, Report, copy_page

NAME = 'html'
SUFFIXES = ('.html', '.htm')
TEXT_SUFFIXES = ('.html', '.htm', '.css', '.svg')
FONT_CSS_HOST = 'fonts.googleapis.com'
FONT_FILE_HOST = 'fonts.gstatic.com'
FONT_HOSTS = (FONT_CSS_HOST, FONT_FILE_HOST)

# Loads from outside a page: the patterns scratchpad's site.py check uses.
OUTSIDE = (
    re.compile(r"""\b(?:src|href|xlink:href|srcset|action|formaction|poster|data|background)\s*=\s*["']\s*"""
               r"""((?:https?:|wss?:)?//[^"'\s>]+)""", re.IGNORECASE),
    re.compile(r"""url\(\s*["']?\s*((?:https?:)?//[^"')\s]+)""", re.IGNORECASE),
    re.compile(r"""@import\s+(?:url\()?\s*["']?\s*((?:https?:)?//[^"')\s;]+)""", re.IGNORECASE),
    re.compile(r"""\b(?:fetch|import|importScripts|WebSocket|EventSource|Worker|sendBeacon)\s*\(\s*["'`]\s*"""
               r"""((?:https?:|wss?:)?//[^"'`\s]+)""", re.IGNORECASE),
)
# Attributes that only navigate or name things, never load: <a href>, <link rel=canonical>, ...
NAVIGATING_TAGS = ('a', 'area', 'base', 'form')
LOADING_RELS = {'stylesheet', 'icon', 'shortcut', 'preload', 'modulepreload', 'prefetch', 'manifest',
                'apple-touch-icon', 'mask-icon', 'preconnect', 'dns-prefetch'}

TAG = re.compile(r'<(script|link)\b[^>]*>', re.IGNORECASE)
ATTR = re.compile(r"""\b([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""")
FONT_IMPORT = re.compile(r"""@import\s+(?:url\(\s*)?["']?((?:https?:)?//fonts\.googleapis\.com/[^"')\s;]+)["']?\s*\)?"""
                         r"""\s*;?""", re.IGNORECASE)
CSS_URL = re.compile(r"""url\(\s*(["']?)([^"')]+?)\1\s*\)""", re.IGNORECASE)
# An exact version: a path segment NAME@1.2.3 (npm CDNs) or 1.2.3 after the name (cdnjs), or a file named
# NAME-1.2.3.min.js (plotly's CDN).
EXACT = re.compile(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')
VERSIONED_FILE = re.compile(r'^(.+?)-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)((?:\.min)?\.(?:m?js|css))$')
RELATIVE = re.compile(r"""\b(?:src|href)\s*=\s*["']([^"'#?:]+?)(?:[?#][^"']*)?["']""", re.IGNORECASE)
RELATIVE_URL = re.compile(r"""url\(\s*["']?([^"')\s#?:]+?)(?:[?#][^"')]*)?["']?\s*\)""", re.IGNORECASE)
RELATIVE_FETCH = re.compile(r"""\bfetch\(\s*["'`]([^"'`:$]+?)(?:[?#][^"'`]*)?["'`]""")


def absolute(url):
    return 'https:' + url if url.startswith('//') else url


def line_of(text, pos):
    return text.count('\n', 0, pos) + 1


def attrs(tag):
    return {m.group(1).lower(): next(g for g in m.groups()[1:] if g is not None) for m in ATTR.finditer(tag)}


def rel_from(file_rel, target_rel):
    """TARGET_REL (a path in the bundle) as a link from the file at FILE_REL."""
    return posixpath.relpath(target_rel, posixpath.dirname(file_rel) or '.')


class Bundler:
    def __init__(self, out, policy):
        self.out = Path(out)
        self.policy = policy
        self.problems = []
        self.notes = []
        self.font_css = {}        # Google Fonts CSS URL -> rewritten CSS
        self.font_files = {}      # font URL -> file name in fonts/
        self.font_manifest = []
        self.vendored = {}        # URL -> path in the bundle
        self.vendor_manifest = []

    def problem(self, rel, text, pos, what):
        self.problems.append(Problem(f'{rel}:{line_of(text, pos)}' if text is not None else rel, what))

    # -- fonts ---------------------------------------------------------------------------------

    def font_stylesheet(self, url):
        """Download the Google Fonts CSS at URL and its faces; False when it cannot."""
        url = absolute(html.unescape(url))
        if url in self.font_css:
            return True
        try:
            css = fetch.fetch(url, 'fonts').decode()
        except (fetch.FetchError, UnicodeDecodeError) as error:
            self.problems.append(Problem(url, f'cannot download the font CSS: {error}'))
            return False

        def local(match):
            face = absolute(match.group(2))
            if urllib.parse.urlsplit(face).hostname != FONT_FILE_HOST:
                return match.group(0)
            if face not in self.font_files:
                try:
                    data = fetch.fetch(face, 'fonts')
                except fetch.FetchError as error:
                    self.problems.append(Problem(face, f'cannot download the font: {error}'))
                    return match.group(0)
                name = posixpath.basename(urllib.parse.urlsplit(face).path)
                if name in ('', '.', '..'):
                    name = 'font'
                if name in self.font_files.values():
                    name = f'{fetch.sha256(face.encode())[:8]}-{name}'
                (self.out / 'fonts').mkdir(exist_ok=True)
                (self.out / 'fonts' / name).write_bytes(data)
                self.font_files[face] = name
                self.font_manifest.append({'file': name, 'url': face, 'sha256': fetch.sha256(data)})
            return f'url({self.font_files[face]})'

        self.font_css[url] = CSS_URL.sub(local, css)
        return True

    def fonts_href(self, rel):
        return rel_from(rel, 'fonts/fonts.css')

    def rewrite_fonts(self, rel, text):
        if rel.endswith(('.html', '.htm')):
            def link(match):
                a = attrs(match.group(0))
                host = urllib.parse.urlsplit(absolute(html.unescape(a.get('href', '')))).hostname
                if host not in FONT_HOSTS:
                    return match.group(0)
                rels = set(a.get('rel', '').lower().split())
                if rels & {'preconnect', 'dns-prefetch'}:
                    return ''   # nothing to connect to once the fonts are in the bundle
                if host == FONT_CSS_HOST and 'stylesheet' in rels and self.font_stylesheet(a['href']):
                    return f'<link rel="stylesheet" href="{self.fonts_href(rel)}">'
                return match.group(0)
            text = re.sub(r'<link\b[^>]*>', link, text, flags=re.IGNORECASE)

        def imported(match):
            if self.font_stylesheet(match.group(1)):
                return f'@import url("{self.fonts_href(rel)}");'
            return match.group(0)
        return FONT_IMPORT.sub(imported, text)

    # -- CDN files -----------------------------------------------------------------------------

    def pinned(self, url):
        """(package, version, path after the version) for an exact-version CDN URL; (package, range, None)
        for a range or tag; None when the URL names no version."""
        parts = [p for p in urllib.parse.urlsplit(url).path.split('/') if p]
        for i, part in enumerate(parts):
            if '@' in part.lstrip('@'):
                name, _, version = part.lstrip('@').rpartition('@')
                scope = parts[i - 1] + '/' if i > 0 and parts[i - 1].startswith('@') else ''
                package = scope + ('@' if part.startswith('@') else '') + name
                if not EXACT.match(version):
                    return package, version, None
                return package, version, '/'.join(parts[i + 1:]) or name.split('/')[-1] + '.js'
            if i > 0 and EXACT.match(part):
                return parts[i - 1], part, '/'.join(parts[i + 1:]) or parts[i - 1] + '.js'
        m = VERSIONED_FILE.match(parts[-1]) if parts else None
        return (m.group(1), m.group(2), parts[-1]) if m else None

    def vendor(self, url, rel, text, pos):
        """URL downloaded into vendor/; its path in the bundle, or None (with a problem when it should be)."""
        url = absolute(html.unescape(url))
        if url in self.vendored:
            return self.vendored[url]
        found = self.pinned(url)
        if found is None:
            return None
        package, version, rest = found
        if rest is None:
            self.problem(rel, text, pos, f'{url} names {package}@{version}, not an exact version: pin one '
                                         f'(like {package}@1.2.3), so the page is the same every time')
            return None
        if any(part in ('.', '..') for part in rest.split('/')):
            self.problem(rel, text, pos, f'{url} names a path outside its package ({rest}); viz will not save it')
            return None
        try:
            data = fetch.fetch(url, 'vendor')
        except fetch.FetchError as error:
            self.problem(rel, text, pos, f'cannot download {url}: {error}')
            return None
        path = posixpath.join('vendor', f'{package.replace("/", "__")}@{version}', rest)
        if not self.save(path, data):
            self.problem(rel, text, pos, f'{url} would be saved outside vendor/ ({path})')
            return None
        self.vendored[url] = path
        self.vendor_manifest.append({'name': package, 'version': version, 'file': path.removeprefix('vendor/'),
                                     'url': url, 'sha256': fetch.sha256(data)})
        if path.endswith('.css'):
            self.vendor_css_assets(url, path, data)
        return path

    def vendor_css_assets(self, url, path, data):
        """Files a vendored stylesheet names relatively (KaTeX's fonts), downloaded beside it."""
        try:
            css = data.decode()
        except UnicodeDecodeError:
            return
        for m in CSS_URL.finditer(css):
            ref = m.group(2).strip()
            if ':' in ref or ref.startswith(('/', '#')):
                continue
            target = urllib.parse.urljoin(url, ref.split('#')[0].split('?')[0])
            local = posixpath.normpath(posixpath.join(posixpath.dirname(path), ref.split('#')[0].split('?')[0]))
            if target in self.vendored:
                continue
            if not self.within_vendor(local):
                self.problems.append(Problem(path, f'names {ref}, outside vendor/; viz will not save it'))
                continue
            try:
                asset = fetch.fetch(target, 'vendor')
            except fetch.FetchError as error:
                self.problems.append(Problem(path, f'cannot download {target}: {error}'))
                continue
            self.save(local, asset)
            self.vendored[target] = local

    def within_vendor(self, path):
        """Whether PATH (relative to the bundle) is a file under vendor/, as written and as resolved."""
        parts = path.split('/')
        if parts[0] != 'vendor' or len(parts) < 2 or any(p in ('', '.', '..') for p in parts):
            return False
        return (self.out / path).resolve().is_relative_to(self.out.resolve() / 'vendor')

    def save(self, path, data):
        """Write DATA at PATH under vendor/; False, writing nothing, when PATH is not under vendor/."""
        if not self.within_vendor(path):
            return False
        dest = self.out / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        return True

    def rewrite_cdn(self, rel, text):
        def tag(match):
            original = match.group(0)
            a = attrs(original)
            name = match.group(1).lower()
            key = 'src' if name == 'script' else 'href'
            url = a.get(key, '')
            if not re.match(r'(?:https?:)?//', url) or urllib.parse.urlsplit(absolute(url)).hostname in FONT_HOSTS:
                return original
            if name == 'link' and not set(a.get('rel', '').lower().split()) & {'stylesheet', 'modulepreload'}:
                return original
            path = self.vendor(url, rel, text, match.start())
            if path is None:
                return original
            return original.replace(url, rel_from(rel, path), 1)
        return TAG.sub(tag, text)

    # -- checks --------------------------------------------------------------------------------

    def outside(self, rel, text):
        if self.policy.network:
            return
        for pattern in OUTSIDE:
            for m in pattern.finditer(text):
                start = text.rfind('<', 0, m.start())
                tag = re.match(r'<\s*([\w:-]+)', text[start:m.start() + 1]) if start >= 0 else None
                name = tag.group(1).lower() if tag else ''
                if pattern is OUTSIDE[0] and name in NAVIGATING_TAGS:
                    continue
                if pattern is OUTSIDE[0] and name == 'link':
                    end = text.find('>', m.start())
                    rels = set(attrs(text[start:end + 1]).get('rel', '').lower().split())
                    if not rels & LOADING_RELS:
                        continue
                self.problem(rel, text, m.start(1), f'loads {m.group(1)} from outside the page')

    def links(self, rel, text):
        patterns = [RELATIVE_URL] if rel.endswith('.css') else [RELATIVE, RELATIVE_URL, RELATIVE_FETCH]
        base = posixpath.dirname(rel)
        for pattern in patterns:
            for m in pattern.finditer(text):
                ref = urllib.parse.unquote(m.group(1).strip())
                if not ref:
                    continue
                if ref.startswith('/'):
                    self.problem(rel, text, m.start(1), f'{ref} is relative to the site root, not the page: '
                                                        'make it relative to this file')
                    continue
                target = posixpath.normpath(posixpath.join(base, ref))
                if target.startswith('../') or target == '..':
                    self.problem(rel, text, m.start(1), f'{ref} points outside the page')
                    continue
                path = self.out / target
                if path.is_dir():
                    path = path / 'index.html'
                if not path.is_file():
                    self.problem(rel, text, m.start(1), f'{ref} is not in the bundle (missing, or not a file a '
                                                        'browser reads: [bundle] include adds it)')

    # -- the whole page ------------------------------------------------------------------------

    def write_manifests(self):
        if self.font_css:
            (self.out / 'fonts').mkdir(exist_ok=True)
            css = '\n'.join(f'/* {url} */\n{css.strip()}\n' for url, css in self.font_css.items())
            (self.out / 'fonts' / 'fonts.css').write_text(css)
            sources = [{'file': 'fonts.css', 'url': url} for url in self.font_css]
            (self.out / 'fonts' / 'MANIFEST.json').write_text(
                json.dumps(sources + self.font_manifest, indent=2) + '\n')
        if self.vendor_manifest:
            path = self.out / 'vendor' / 'MANIFEST.json'
            entries = []
            if path.is_file():
                try:
                    entries = json.loads(path.read_text())
                except ValueError:
                    entries = None
                if not isinstance(entries, list):
                    self.problems.append(Problem('vendor/MANIFEST.json', 'is not a JSON list, so viz cannot add '
                                                                         'the files it downloaded'))
                    return
            known = {e.get('url') for e in entries if isinstance(e, dict)}
            entries += [e for e in self.vendor_manifest if e['url'] not in known]
            path.write_text(json.dumps(entries, indent=2) + '\n')


def bundle(page, out, policy, include=(), exclude=()):
    b = Bundler(out, policy)
    entry, files = copy_page(page, out, include, exclude, problems=b.problems)
    for rel in files:
        if not rel.lower().endswith(TEXT_SUFFIXES):
            continue
        path = b.out / rel
        text = path.read_text(errors='surrogateescape')
        new = text if rel.endswith('.svg') else b.rewrite_cdn(rel, b.rewrite_fonts(rel, text))
        if new != text:
            path.write_text(new, errors='surrogateescape')
    b.write_manifests()
    for rel in sorted(p.relative_to(b.out).as_posix() for p in b.out.rglob('*') if p.is_file()):
        if rel.lower().endswith(TEXT_SUFFIXES):
            text = (b.out / rel).read_text(errors='surrogateescape')
            b.outside(rel, text)
            b.links(rel, text)
    if b.font_files:
        b.notes.append(f'{len(b.font_files)} font file(s) downloaded into fonts/')
    if b.vendored:
        b.notes.append(f'{len(b.vendored)} CDN file(s) downloaded into vendor/')
    every = sorted(p.relative_to(b.out).as_posix() for p in b.out.rglob('*') if p.is_file())
    return Report(entry=entry, format=NAME, files=every, problems=b.problems, notes=b.notes)


def check(page, out, policy):
    """What would break portably: the problems of a bundle written into OUT (a scratch folder)."""
    return bundle(page, out, policy).problems


def to_pdf(page, out, policy):
    """PAGE printed to OUT/NAME.pdf by Chromium: its print CSS, the light theme, the paper config.toml names
    (`paper = "Letter"`; A4 by default). The page is bundled first and printed offline."""
    from .. import browser
    from ..config import settings
    from . import BundleError, pdf
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    name = (page.folder.name if page.folder else page.entry.stem) + '.pdf'
    paper = settings().get('paper', 'A4')
    with tempfile.TemporaryDirectory(prefix='viz-pdf-') as tmp:
        report = bundle(page, tmp, policy)
        if report.problems:
            return Report(entry=name, format='pdf', problems=report.problems)
        try:
            result = browser.run(['--offline', f'--pdf={out / name}', f'--paper={paper}', f'--root={tmp}',
                                  str(Path(tmp) / report.entry)], capture=True)
        except browser.BrowserError as error:
            raise BundleError(str(error)) from None
        if result.returncode != 0 or not (out / name).is_file():
            raise BundleError(f'printing {page.entry} to pdf failed:\n{(result.stderr or result.stdout).strip()}')
    found = [Problem(name, line.strip().removeprefix('problem: '))
             for line in result.stdout.splitlines() if line.strip().startswith('problem:')]
    return Report(entry=name, format='pdf', files=[name], problems=found + pdf.problems(out / name))


# Other formats an html page can become.
EXPORTS = {'pdf': to_pdf}
