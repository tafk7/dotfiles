"""Targets: where a page is published, for whom, under which rules; `viz targets` and `viz publish`.

Three targets are built in (preview, file and live) and cannot be redefined. Any number more are config
files, CONFIG/targets.d/NAME.toml, of a configurable type. Every target carries its audience and rules text,
which `viz targets NAME` shows, so an agent learns before publishing who will see a page.

Publishing is a command only. The server never imports this package: a page it serves could otherwise copy
any private draft to a shared site.
"""
import datetime
import json
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .. import formats, manifest
from ..config import CONFIG, die, settings

TARGETS_DIR = CONFIG / 'targets.d'
RESERVED = ('preview', 'file', 'live')
COMMON_KEYS = {
    'type': str, 'description': str, 'audience': str, 'rules': str, 'formats': list, 'network': bool,
    'provenance': list, 'required': list, 'manifest': dict,
}


class TargetError(Exception):
    """A target cannot take this page, or its config is wrong; the message says why."""


@dataclass
class Target:
    """A target's settings. Built-in targets and each configurable type subclass it."""
    name: str
    type: str
    description: str = ''
    audience: str = ''
    rules: str = ''
    formats: list | None = None        # None: any format
    network: bool = False
    provenance: list = field(default_factory=lambda: list(manifest.DEFAULT_PROVENANCE))
    required: list = field(default_factory=list)
    manifest: dict = field(default_factory=dict)
    path: Path | None = None           # its config file; None for a built-in
    config: dict = field(default_factory=dict)
    builtin = False
    records = True                     # whether a publication is appended to the draft
    usage = ''

    def takes(self, fmt):
        return self.formats is None or fmt in self.formats

    def check_config(self):
        """Raise TargetError when a configured target's own keys are wrong."""

    def place(self, job, last, reuse):
        """Where JOB's page goes and its URL, changing nothing: (place, url, notes). LAST is the draft's last
        record for this target, which a republish reuses (REUSE) so the URL never moves."""
        raise NotImplementedError

    def publish(self, job, bundle_dir, text):
        """Put the bundle and the published manifest TEXT at job.place; the record's extra fields."""
        raise NotImplementedError

    def dry_run_lines(self, job):
        """What `--dry-run` adds for this target (a git target's push policy)."""
        return []

    def describe(self):
        """The settings `viz targets NAME` shows, after the common ones."""
        return []

    def as_json(self):
        return {'name': self.name, 'type': self.type, 'builtin': self.builtin,
                'path': str(self.path) if self.path else None, 'description': self.description,
                'audience': self.audience, 'rules': self.rules, 'formats': self.formats, 'network': self.network,
                'provenance': self.provenance,
                'required': list(manifest.MINIMUM) + [r for r in self.required if r not in manifest.MINIMUM],
                'usage': self.usage, **{k: v for k, v in self.config.items() if k not in COMMON_KEYS}}


@dataclass
class Broken:
    """A target file that cannot be used, and why."""
    name: str
    path: Path
    error: str
    type: str = '?'

    def as_json(self):
        return {'name': self.name, 'type': self.type, 'path': str(self.path), 'error': self.error}


@dataclass
class Job:
    """One publication: the page, the target, and what the command line asked for."""
    page: manifest.Page
    target: Target
    slug: str = ''
    out: str | None = None             # file target: where to write
    message: str | None = None         # git target: the commit message
    format: str = ''
    report: formats.Report | None = None
    place: str = ''
    url: str = ''
    notes: list = field(default_factory=list)
    first: datetime.date | None = None  # the first publication's day (today for a first one)


def types():
    """Configurable target types: type name -> Target subclass."""
    return {}


def builtins():
    from .file import FileTarget
    from .preview import PreviewTarget
    return {'preview': PreviewTarget(), 'file': FileTarget()}


def load(path):
    """The Target in config file PATH, or Broken."""
    name = path.stem
    if name in RESERVED:
        return Broken(name, path, f'{name} is a built-in target and cannot be redefined; rename the file')
    try:
        data = manifest.read(path)
    except (OSError, ValueError) as error:
        return Broken(name, path, str(error))
    kind = data.get('type')
    cls = types().get(kind)
    if cls is None:
        known = ', '.join(sorted(types())) or 'none yet'
        return Broken(name, path, f'type {kind!r} is not a configurable target type (known: {known})', str(kind))
    keys = {**COMMON_KEYS, **cls.KEYS}
    problems = [f'unknown key {k!r}' for k in data if k not in keys]
    problems += [f'{k} should be {keys[k].__name__}' for k, v in data.items()
                 if k in keys and not isinstance(v, keys[k])]
    problems += [f'{k} is required' for k in getattr(cls, 'REQUIRED_KEYS', ()) if k not in data]
    if problems:
        return Broken(name, path, '; '.join(problems), kind)
    common = {k: data[k] for k in COMMON_KEYS if k in data and k != 'type'}
    try:
        target = cls(name=name, type=kind, path=path, config=data, **common)
        target.check_config()
    except TargetError as error:
        return Broken(name, path, str(error), kind)
    return target


def configured():
    """Every file in targets.d, loaded: Target or Broken, by name."""
    if not TARGETS_DIR.is_dir():
        return []
    return [load(p) for p in sorted(TARGETS_DIR.glob('*.toml')) if not p.name.startswith('.')]


def everything():
    return list(builtins().values()) + configured()


def find(name):
    for target in everything():
        if target.name == name:
            if isinstance(target, Broken):
                die(f'target {name} ({target.path}) cannot be used: {target.error}')
            return target
    names = ', '.join(t.name for t in everything())
    die(f'no target named {name}; the targets are: {names} (viz targets lists them)')
    return None


# ---------------------------------------------------------------------------
# viz targets
# ---------------------------------------------------------------------------

def _home(path):
    home = str(Path.home())
    text = str(path)
    return '~' + text[len(home):] if text == home or text.startswith(home + '/') else text


def cmd_targets(args):
    if args.name:
        target = next((t for t in everything() if t.name == args.name), None)
        if target is None:
            die(f'no target named {args.name}; viz targets lists them')
        if args.json:
            print(json.dumps(target.as_json(), indent=2))
            return
        print(show(target))
        return
    listed = everything()
    if args.json:
        print(json.dumps([t.as_json() for t in listed], indent=2))
        return
    width = max(len(t.name) for t in listed)
    for t in listed:
        kind = 'built in' if getattr(t, 'builtin', False) else t.type
        if isinstance(t, Broken):
            what = f'BROKEN: {t.error}'
        else:
            what = t.audience
        where = f'  ({_home(t.path)})' if t.path else ''
        print(f'{t.name:<{width}}  {kind:<8}  {what}{where}')


def show(t):
    """Everything about target T, its rules text in full."""
    if isinstance(t, Broken):
        return f'{t.name}  ({_home(t.path)})\nBROKEN: {t.error}'
    lines = [f'{t.name}  ({"built in" if t.builtin else t.type + ", " + _home(t.path)})']
    if t.description:
        lines.append(f'description: {t.description}')
    lines.append(f'audience:    {t.audience or "(not said)"}')
    lines.append(f'formats:     {", ".join(t.formats) if t.formats is not None else "any"}')
    if not t.builtin:
        required = list(manifest.MINIMUM) + [r for r in t.required if r not in manifest.MINIMUM]
        lines.append(f'network:     {"allowed" if t.network else "not allowed: a page loads nothing from outside"}')
        lines.append(f'provenance:  {", ".join(t.provenance) or "none"} (the [source] fields a published copy keeps)')
        lines.append(f'required:    {", ".join(required)}')
    lines += t.describe()
    if t.usage:
        lines.append(f'use:         {t.usage}')
    if t.rules:
        lines += ['rules:'] + ['  ' + line if line else '' for line in t.rules.strip().splitlines()]
    return '\n'.join(lines)


def status_line():
    """For `viz status`: how many targets, and any that are broken."""
    listed = everything()
    broken = [t for t in listed if isinstance(t, Broken)]
    names = ', '.join(t.name for t in listed if not isinstance(t, Broken))
    line = f'{len(listed) - len(broken)} ({names}); viz targets lists them'
    return line + ''.join(f'\n          broken: {_home(t.path)}: {t.error}' for t in broken)


# ---------------------------------------------------------------------------
# viz publish
# ---------------------------------------------------------------------------

def parse_sets(pairs):
    out = []
    for pair in pairs or []:
        key, sep, val = pair.partition('=')
        if not sep or not key or any(not part for part in key.split('.')):
            die(f'--set takes KEY=VALUE (a dotted KEY for a table: source.run=1234), not {pair!r}')
        out.append((key, val))
    return out


def pick_format(page, target, wanted):
    """The format to publish PAGE in: --format, else the page's own if the target takes it, else an export."""
    own = page.format
    if wanted:
        if not target.takes(wanted):
            raise TargetError(f'{target.name} takes {", ".join(target.formats)}, not {wanted}')
        return wanted
    if target.takes(own):
        return own
    for fmt in formats.exports(own):
        if target.takes(fmt):
            return fmt
    raise TargetError(f'{target.name} takes {", ".join(target.formats)}; this page is {own or "of no known format"}'
                      ' and viz cannot export it to any of those')


def default_slug(page):
    return page.folder.name if page.folder else page.entry.stem


def check_slug(slug):
    if not slug or slug.startswith('.') or '/' in slug or slug in ('..',) or any(c.isspace() for c in slug):
        die(f'--as takes a plain name (letters, digits, - _ .), not {slug!r}')
    return slug


def cmd_publish(args):
    target = find(args.to)
    if args.push:
        if not hasattr(target, 'push_pending'):
            die(f'--push is for a git target; {target.name} is {target.type}')
        sys.exit(target.push_pending(args))
    if not args.page:
        die('viz publish PAGE --to TARGET: which page?')
    path = Path(args.page).expanduser()
    if not path.exists():
        die(f'no such page: {args.page}')
    try:
        page = manifest.locate(path)
    except ValueError as error:
        die(str(error))
    if target.name == 'preview':
        return target.open(page, args)
    job = Job(page=page, target=target, out=args.out, message=args.message)
    try:
        return publish(job, args)
    except (TargetError, formats.BundleError) as error:
        die(str(error))
    return None


def publish(job, args):
    page, target = job.page, job.target
    lacking = manifest.missing(page.data, target.required)
    if lacking:
        hint = '' if page.manifest.exists() else ' (it does not exist yet: write it, or make pages with viz path)'
        raise TargetError(f'{page.manifest} lacks {", ".join(lacking)}, which {target.name} needs{hint}')
    for warning in manifest.warnings(page.data):
        print(f'viz: warning: {warning}', file=sys.stderr)
    job.format = fmt = pick_format(page, target, args.format)
    last = manifest.last_record(page.data, target.name)
    job.slug = check_slug(args.as_name) if args.as_name else default_slug(page)
    job.first = manifest.first_published(page.data, target.name) or manifest.today()
    job.place, job.url, job.notes = target.place(job, last, reuse=not args.as_name)
    with tempfile.TemporaryDirectory(prefix='viz-publish-') as tmp:
        bundle_dir = Path(tmp) / 'bundle'
        job.report = report = formats.bundle(page, fmt, bundle_dir, formats.Policy(network=target.network))
        if report.problems:
            raise formats.BundleError(f'{page.entry} is not portable:\n  '
                                      + '\n  '.join(str(p) for p in report.problems))
        defaults = [{'author': settings()['author']}] if settings().get('author') else []
        data = manifest.compose(page.data, target.name, defaults=[*defaults, target.manifest],
                                provenance=target.provenance, sets=parse_sets(args.set), entry=report.entry,
                                fmt=report.format)
        data = order(data)
        text = manifest.dumps(data, comment=f'Published by viz publish --to {target.name}.')
        if args.dry_run:
            return dry_run(job, report, text)
        extra = target.publish(job, bundle_dir, text) or {}
    if target.records:
        record = {'target': target.name, 'at': now(), 'place': job.place}
        if job.url:
            record['url'] = job.url
        record.update(extra)
        manifest.append(page.manifest, 'published', record)
    for note in job.notes:
        print(f'viz: {note}', file=sys.stderr)
    print(job.url or job.place)
    return None


ORDER = ('title', 'summary', 'kind', 'project', 'audience', 'author', 'date', 'updated', 'format', 'entry')


def order(data):
    return {**{k: data[k] for k in ORDER if k in data}, **{k: v for k, v in data.items() if k not in ORDER}}


def now():
    return datetime.datetime.now(datetime.UTC).replace(microsecond=0)


def dry_run(job, report, text):
    t = job.target
    print(f'target:   {t.name} ({"built in" if t.builtin else t.type})')
    print(f'place:    {job.place}')
    if job.url:
        print(f'url:      {job.url}')
    for line in t.dry_run_lines(job):
        print(line)
    print(f'format:   {report.format}, entry {report.entry}')
    print(f'files:    {len(report.files)}')
    for name in report.files:
        print(f'          {name}')
    for note in report.notes + job.notes:
        print(f'note:     {note}')
    print('manifest:')
    for line in text.splitlines():
        print(f'          {line}' if line else '')
    print('dry run: nothing was written')


def replace_tree(src, dest):
    """Make DEST hold exactly what SRC holds (DEST's parent must exist)."""
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
