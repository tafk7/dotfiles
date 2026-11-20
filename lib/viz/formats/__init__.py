"""Formats: what the CLI must know to check a page and make it portable.

A format with a module here (html.py, ...) defines NAME, SUFFIXES, check(), bundle() and EXPORTS, the other
formats it can become. A format without one (pptx, typst, latex today) is pass-through: its portable form is
the entry file itself. Authoring guidance for a format lives in the plugin (references/formats/<fmt>.md).
"""
import fnmatch
import shutil
from dataclasses import dataclass, field
from pathlib import Path

# What a browser reads from a page's folder; anything else (generators, notes, raw data) stays in the draft.
BROWSER_SUFFIXES = {
    '.html', '.htm', '.css', '.js', '.mjs', '.json', '.csv', '.tsv', '.svg', '.png', '.jpg', '.jpeg', '.gif',
    '.webp', '.avif', '.ico', '.woff', '.woff2', '.ttf', '.otf', '.pdf', '.txt',
}


class BundleError(Exception):
    """A page cannot be made portable; the message lists the problems."""


@dataclass
class Problem:
    where: str      # a file in the page, with a line number when there is one
    what: str

    def __str__(self):
        return f'{self.where}: {self.what}'


@dataclass
class Report:
    """What a bundle holds: its entry (relative to the bundle), its files, and what is wrong with it."""
    entry: str
    format: str
    files: list[str] = field(default_factory=list)
    problems: list[Problem] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


@dataclass
class Policy:
    """What a target allows a bundle: loads from outside it (network)."""
    network: bool = False


def module(fmt):
    """The module of format FMT, or None for a pass-through format."""
    return MODULES.get(fmt)


def copy_page(page, out, include=(), exclude=()):
    """Copy what a browser reads from PAGE's folder into OUT; a loose html file is copied alone as index.html.

    Hidden files and folders, generators (*.py), page.toml and anything EXCLUDE matches are skipped; INCLUDE
    adds files of any other suffix. Patterns are globs on the path within the folder (data/*.parquet).
    Returns the bundle's entry and its files.
    """
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    if page.loose:
        name = 'index.html' if page.entry.suffix.lower() in ('.html', '.htm') else page.entry.name
        shutil.copy2(page.entry, out / name)
        return name, [name]
    files = []
    for path in sorted(page.folder.rglob('*')):
        rel = path.relative_to(page.folder).as_posix()
        if not path.is_file() or any(part.startswith('.') for part in Path(rel).parts):
            continue
        if path.parent == page.folder and (path.name == 'page.toml' or path.name.endswith('.page.toml')):
            continue
        wanted = path.suffix.lower() in BROWSER_SUFFIXES or _matches(rel, include)
        if not wanted or path.suffix == '.py' or _matches(rel, exclude):
            continue
        (out / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, out / rel)
        files.append(rel)
    return page.entry.relative_to(page.folder).as_posix(), files


def _matches(rel, patterns):
    return any(fnmatch.fnmatch(rel, p) for p in patterns)


def bundle(page, fmt, out, policy=None):
    """Write PAGE's portable form in format FMT into OUT (a new or empty folder); a Report.

    The page's own format is bundled by its module (html.py, pdf.py, image.py); a format without one is
    pass-through, its entry file alone. Another format must be an export of the page's. Problems are in the
    Report; BundleError means there is nothing to bundle.
    """
    policy = policy or Policy()
    source = page.format
    settings = page.data.get('bundle', {}) if isinstance(page.data.get('bundle'), dict) else {}
    include, exclude = settings.get('include', []), settings.get('exclude', [])
    if not page.entry.is_file():
        raise BundleError(f'{page.entry}: no such file (the page\'s entry)')
    if fmt != source:
        exporter = getattr(module(source), 'EXPORTS', {}).get(fmt)
        if exporter is None:
            raise BundleError(f'viz cannot make {fmt} from {source or "this page"}')
        return exporter(page, out, policy)
    mod = module(fmt)
    if mod is not None:
        return mod.bundle(page, out, policy, include=include, exclude=exclude)
    Path(out).mkdir(parents=True, exist_ok=True)
    entry = page.entry.name
    shutil.copy2(page.entry, Path(out) / entry)
    return Report(entry=entry, format=fmt, files=[entry])


def exports(fmt):
    """The formats a page of format FMT can be exported to."""
    return sorted(getattr(module(fmt), 'EXPORTS', {}))


# Imported last: the modules use Problem, Report and copy_page from here.
from . import html, image, pdf

MODULES = {html.NAME: html, pdf.NAME: pdf, **dict.fromkeys(image.NAMES, image)}
