"""page.toml, the manifest beside every page: the stub `viz path` writes, reading, checking, and appending.

A folder page keeps FOLDER/page.toml, whose `entry` names the page in it (default index.html). A loose file
keeps a sidecar named after the whole file, report.html.page.toml, so report.html and report.pdf never share
one. viz writes a draft's manifest once, as a stub, and afterwards only appends [[published]] tables, so an
agent's comments and order survive. A published copy's manifest is written fresh by dumps().
"""
import datetime
import json
import os
import re
import socket
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import tomllib

from .config import ROOT, settings

NAME = 'page.toml'
SIDECAR = '.page.toml'
# The forms in the plugin's forms.md. Free text is allowed; viz only warns.
KINDS = ('answer', 'explainer', 'walkthrough', 'review', 'comparison', 'status', 'dashboard', 'explorer',
         'report', 'tool', 'figure', 'set')
# What `viz publish` refuses a page without; a target may require more.
MINIMUM = ('title', 'summary', 'source.generator')
# Suffixes whose format name is not the suffix itself.
FORMAT_ALIASES = {'htm': 'html', 'jpeg': 'jpg'}


def format_of(entry):
    """The format of a page from its entry's suffix: html, pdf, svg, png, ...; '' without one."""
    suffix = Path(entry).suffix.lower().lstrip('.')
    return FORMAT_ALIASES.get(suffix, suffix)


def today():
    """The local day: drafts are filed under it, and it is what `date` and `updated` record."""
    return datetime.date.today()  # noqa: DTZ011


# ---------------------------------------------------------------------------
# Finding a page's manifest
# ---------------------------------------------------------------------------

@dataclass
class Page:
    """A page on disk: where its manifest is, its folder (None for a loose file) and its entry file."""
    manifest: Path               # page.toml or FILE.page.toml; it may not exist yet
    entry: Path                  # the page itself
    folder: Path | None = None   # a folder page's folder
    data: dict = field(default_factory=dict)

    @property
    def loose(self):
        return self.folder is None

    @property
    def format(self):
        return self.data.get('format') or format_of(self.entry)


def locate(path):
    """The Page at PATH: a folder with page.toml, that page.toml, a file in such a folder, or a loose file.

    A file belongs to the nearest folder above it with a page.toml, looking no higher than VIZ_DIR's dated
    folders for a file under VIZ_DIR and no higher than its own directory elsewhere. Any other file is loose,
    with a sidecar manifest beside it.
    """
    path = Path(path).expanduser().resolve()
    if path.name == NAME and path.is_file():
        path = path.parent
    if path.is_dir():
        return _folder_page(path)
    sidecar = path.with_name(path.name + SIDECAR)
    if not sidecar.exists():
        for folder in _candidate_folders(path):
            if (folder / NAME).is_file():
                page = _folder_page(folder)
                if 'entry' not in page.data:
                    page.entry = path
                return page
    return Page(manifest=sidecar, entry=path, data=read(sidecar) if sidecar.is_file() else {})


def _folder_page(folder):
    manifest = folder / NAME
    data = read(manifest) if manifest.is_file() else {}
    return Page(manifest=manifest, entry=folder / data.get('entry', 'index.html'), folder=folder, data=data)


def _candidate_folders(path):
    """Folders above PATH that may hold its page.toml, nearest first."""
    if ROOT in path.parents:
        # ROOT/DATE/NAME/...: from the file's directory up to the page folder, never ROOT or a date folder.
        depth = len(path.relative_to(ROOT).parts)
        return [path.parents[i] for i in range(depth - 2)]
    return [path.parent]


def read(path):
    """PATH parsed as TOML; ValueError naming the file when it does not parse."""
    try:
        with open(path, 'rb') as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError as error:
        raise ValueError(f'{path}: {error}') from None


# ---------------------------------------------------------------------------
# Checking
# ---------------------------------------------------------------------------

def lookup(data, dotted):
    """DATA's value at a dotted key (source.generator), or None."""
    value = data
    for key in dotted.split('.'):
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value


def missing(data, required=()):
    """The fields of MINIMUM and REQUIRED that DATA lacks or leaves empty, in order."""
    wanted = list(MINIMUM) + [r for r in required if r not in MINIMUM]
    return [key for key in wanted if lookup(data, key) in (None, '', [], {})]


def warnings(data):
    """What is odd but allowed: a kind not among the forms."""
    kind = data.get('kind')
    if kind and kind not in KINDS:
        return [f'kind {kind!r} is not one of the forms ({", ".join(KINDS)})']
    return []


# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------

def _git(cwd, *args):
    try:
        result = subprocess.run(['git', '-C', str(cwd), *args], capture_output=True, text=True, timeout=10,
                                check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def _remote_url(repo):
    """The fetch URL of the current branch's remote (else origin, else the first), credentials removed."""
    branch = _git(repo, 'symbolic-ref', '--quiet', '--short', 'HEAD')
    names = (_git(repo, 'remote') or '').split()
    name = (branch and _git(repo, 'config', f'branch.{branch}.remote')) or ('origin' if 'origin' in names else
                                                                            names[0] if names else None)
    url = name and _git(repo, 'remote', 'get-url', name)
    # https://user:token@host/... never goes into a manifest.
    return re.sub(r'^([a-z][a-z0-9+.-]*://)[^/@]*@', r'\1', url) if url else None


def provenance(cwd):
    """[source] as viz records it by itself at `viz path`: where it ran, the repository state, host, session."""
    conf = settings().get('provenance', {})
    cwd = Path(cwd)
    source = {'dir': str(cwd)}
    repo = _git(cwd, 'rev-parse', '--show-toplevel')
    if repo:
        source['repo'] = repo
        commit = _git(repo, 'rev-parse', '--short', 'HEAD')
        if commit:
            source['commit'] = commit
            source['dirty'] = bool(_git(repo, 'status', '--porcelain', '--untracked-files=no'))
        remote = _remote_url(repo)
        if remote:
            source['remote'] = remote
    source['host'] = socket.gethostname()
    session = os.environ.get(conf.get('session_env', 'CLAUDE_CODE_SESSION_ID'))
    if session:
        source['session'] = session
    env = {name: os.environ[name] for name in conf.get('env', []) if os.environ.get(name)}
    if env:
        source['env'] = env
    return source


def project_name(source):
    """config's project_from variable's last component, else the repository's name, else None."""
    variable = settings().get('provenance', {}).get('project_from')
    value = variable and os.environ.get(variable)
    if value:
        return Path(value.rstrip('/')).name
    return Path(source['repo']).name if source.get('repo') else None


# ---------------------------------------------------------------------------
# Writing
# ---------------------------------------------------------------------------

def stub(title, entry=None, kind=None, project=None, source=None, day=None):
    """The text of a new draft's page.toml: what viz knows filled in, what the agent fills marked."""
    day = day or today()
    source = dict(source or {})
    generator = source.pop('generator', '')
    lines = [
        "# The page's manifest. viz path wrote it once and never rewrites it: edit it freely.",
        '# viz publish needs title, summary and source.generator. Top-level keys go above [source].',
        f'title = {value(title)}',
        '# fill in: one or two sentences on what the page shows',
        'summary = ""',
        f'# {", ".join(KINDS)}',
        f'kind = {value(kind or "")}',
    ]
    if entry:
        lines += [f'format = {value(format_of(entry))}', f'entry = {value(entry)}']
    else:
        lines += ['# entry = "index.html"     # the page in this folder; format follows its suffix']
    if project:
        lines.append(f'project = {value(project)}')
    lines += ['# who it is for, in words', 'audience = ""', f'date = {value(day)}', f'updated = {value(day)}',
              '', '# [[links]]', '# label = "The pull request"', '# url = "https://example.com/pr/1"',
              '', '[source]']
    lines += [f'{key_of(k)} = {value(v)}' for k, v in source.items()]
    lines += ['# fill in: what made the page: "build.py", a command, or "by hand"',
              f'generator = {value(generator)}']
    return '\n'.join(lines) + '\n'


def create(path, text):
    """Write TEXT to PATH unless it exists; False when it did (an existing manifest is never overwritten)."""
    try:
        with open(path, 'x') as f:
            f.write(text)
    except FileExistsError:
        return False
    return True


def append(path, table, record):
    """Append RECORD as a [[TABLE]] to the manifest at PATH, keeping every byte already there.

    The result is parsed before it replaces the file, so a manifest viz cannot extend is left as it was.
    """
    text = Path(path).read_text()
    block = f'\n[[{table}]]\n' + ''.join(f'{key_of(k)} = {value(v)}\n' for k, v in record.items())
    text = text + ('' if text.endswith('\n') or not text else '\n') + block
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise ValueError(f'{path}: cannot append [[{table}]]: {error}') from None
    _replace(Path(path), text)


def _replace(path, text):
    """Write TEXT to PATH atomically, keeping its mode."""
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f'.{path.name}.')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


BARE_KEY = re.compile(r'[A-Za-z0-9_-]+')


def key_of(key):
    return key if BARE_KEY.fullmatch(key) else json.dumps(key)


def value(v):
    """V as a TOML value: strings, booleans, numbers, dates and times, arrays and inline tables."""
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)   # a TOML basic string
    if isinstance(v, datetime.datetime) and v.utcoffset() == datetime.timedelta(0):
        return v.replace(tzinfo=None).isoformat() + 'Z'
    if isinstance(v, (datetime.date, datetime.datetime, datetime.time)):
        return v.isoformat()
    if isinstance(v, (list, tuple)):
        return '[' + ', '.join(value(x) for x in v) + ']'
    if isinstance(v, dict):
        return '{ ' + ', '.join(f'{key_of(k)} = {value(x)}' for k, x in v.items()) + ' }' if v else '{}'
    raise TypeError(f'cannot write {type(v).__name__} to TOML')


def dumps(data, comment=None):
    """DATA as a TOML document: plain keys first, then tables, then arrays of tables."""
    lines = [f'# {line}' if line else '#' for line in comment.splitlines()] if comment else []
    _table(lines, [], data)
    return '\n'.join(lines).lstrip('\n') + '\n'


def _is_tables(v):
    return isinstance(v, list) and v and all(isinstance(x, dict) for x in v)


def _table(lines, path, data):
    for k, v in data.items():
        if not isinstance(v, dict) and not _is_tables(v):
            lines.append(f'{key_of(k)} = {value(v)}')
    for k, v in data.items():
        name = [*path, key_of(k)]
        if isinstance(v, dict):
            lines += ['', f'[{".".join(name)}]']
            _table(lines, name, v)
        elif _is_tables(v):
            for item in v:
                lines += ['', f'[[{".".join(name)}]]']
                _table(lines, name, item)


# ---------------------------------------------------------------------------
# The published copy
# ---------------------------------------------------------------------------

DRAFT_ONLY = ('to', 'live', 'published', 'bundle')   # never leave the draft
DEFAULT_PROVENANCE = ('commit', 'generator')        # what a published copy keeps of [source]


def merge(low, high):
    """HIGH over LOW, tables merged key by key."""
    out = dict(low)
    for key, val in high.items():
        out[key] = merge(out[key], val) if isinstance(val, dict) and isinstance(out.get(key), dict) else val
    return out


def set_dotted(data, dotted, val):
    *path, last = dotted.split('.')
    for key in path:
        if not isinstance(data.get(key), dict):
            data[key] = {}
        data = data[key]
    data[last] = val


def first_published(draft, target):
    """The local day DRAFT was first published to TARGET, or None."""
    days = [r['at'].astimezone().date() if isinstance(r.get('at'), datetime.datetime) else r.get('at')
            for r in draft.get('published', []) if isinstance(r, dict) and r.get('target') == target]
    days = [d for d in days if isinstance(d, datetime.date)]
    return min(days) if days else None


def last_record(draft, target):
    """DRAFT's last [[published]] record for TARGET, or None."""
    records = [r for r in draft.get('published', []) if isinstance(r, dict) and r.get('target') == target]
    return records[-1] if records else None


def compose(draft, target, defaults=(), provenance=DEFAULT_PROVENANCE, sets=(), day=None, entry=None,
            fmt=None):
    """The published copy's manifest for DRAFT going to TARGET.

    From low to high: DEFAULTS (config.toml's author, then the target's [manifest]), the draft's fields, the
    draft's [to.TARGET], then SETS (dotted KEY, VALUE pairs). viz then sets `date` (the first publication to
    this target), `updated` (today), `entry` and `format` (the bundle's), keeps only the [source] fields
    PROVENANCE lists, and drops what belongs to the draft alone ([to], [live], [bundle], [[published]]) and
    fields left empty.
    """
    day = day or today()
    data = {}
    for layer in defaults:
        data = merge(data, layer)
    data = merge(data, draft)
    own = draft.get('to', {}).get(target) if isinstance(draft.get('to'), dict) else None
    if isinstance(own, dict):
        data = merge(data, own)
    for key, val in sets:
        set_dotted(data, key, val)
    for key in DRAFT_ONLY:
        data.pop(key, None)
    data = {k: v for k, v in data.items() if v not in ('', [], {})}   # the stub's unfilled fields
    data['date'] = first_published(draft, target) or day
    data['updated'] = day
    if entry:
        data['entry'] = entry
    if fmt:
        data['format'] = fmt
    source = data.pop('source', None)
    if isinstance(source, dict):
        kept = {k: v for k, v in source.items() if k in provenance}
        if kept:
            data['source'] = kept
    return data
