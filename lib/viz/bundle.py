"""viz bundle and viz look: a page's portable form, and screenshots of a page or of that form."""
import os
import shutil
import sys
import tempfile
from pathlib import Path

from . import browser, formats, manifest
from .config import STATE, die
from .targets import default_slug
from .targets.file import inside_page, ours

MARK = '# Bundled by viz bundle'


def page_at(arg):
    path = Path(arg).expanduser()
    if not path.exists():
        die(f'no such page: {arg}')
    try:
        return manifest.locate(path)
    except ValueError as error:
        die(str(error))
    return None


def make(page, fmt, out):
    """PAGE's portable form in format FMT, written to OUT (replaced if viz wrote it); the Report."""
    if out.is_symlink():
        die(f'{out} is a link; give --out the path it leads to, or a new one')
    if inside_page(out, page):
        die(f'{out} is inside the page itself; bundle it somewhere else')
    if out.exists() and (not out.is_dir() or (any(out.iterdir()) and not ours(out))):
        die(f'{out} exists and is not a bundle viz wrote; give --out a new or empty folder')
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.viz-bundle-', dir=out.parent) as tmp:
        staged = Path(tmp) / 'bundle'
        try:
            report = formats.bundle(page, fmt, staged)
        except formats.BundleError as error:
            die(str(error))
        data = manifest.compose(page.data, 'bundle', entry=report.entry, fmt=report.format)
        (staged / manifest.NAME).write_text(manifest.dumps(data, comment=f'{MARK[2:]} (a check, not published).'))
        if out.exists():
            shutil.rmtree(out)
        os.replace(staged, out)
    return report


def default_out(page):
    return STATE / 'bundles' / default_slug(page)


def cmd_bundle(args):
    page = page_at(args.page)
    out = Path(args.out).expanduser().absolute() if args.out else default_out(page)
    report = make(page, args.format or page.format, out)
    print(out)
    for note in report.notes:
        print(f'  note: {note}')
    for problem in report.problems:
        print(f'  problem: {problem}')
    if report.problems:
        print(f'{len(report.problems)} problem(s): viz publish refuses this page until they are fixed',
              file=sys.stderr)
        sys.exit(1)


def cmd_look(args):
    """Screenshots of PAGE (or, with --portable, of its bundle, offline) and what broke, through look.py."""
    page = page_at(args.page)
    passed = [f'--{k}' if v is True else f'--{k}={v}' for k, v in (
        ('theme', args.theme), ('width', args.width), ('phone', args.phone), ('full', args.full),
        ('selector', args.selector), ('ready', args.ready), ('js', args.js), ('wait', args.wait))
        if v not in (None, False)]
    shots = (page.folder or page.entry.parent) / '.shots'
    stem = page.folder.name if page.folder else page.entry.stem
    if args.portable:
        out = default_out(page)
        report = make(page, page.format, out)
        for problem in report.problems:
            print(f'  bundle problem: {problem}')
        entry, root = out / report.entry, out
        passed += ['--offline', f'--out={shots / (stem + "-portable")}']
    else:
        entry, root = page.entry, page.folder or page.entry.parent
        passed += [f'--out={shots / stem}']
    if entry.suffix.lower() not in ('.html', '.htm', '.svg'):
        die(f'viz look shows html and svg pages; {entry.name} is {page.format or "something else"}')
    try:
        result = browser.run([*passed, f'--root={root}', str(entry)])
    except browser.BrowserError as error:
        die(str(error))
    sys.exit(result.returncode)
