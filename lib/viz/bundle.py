"""viz bundle: a page's portable form, written where an agent can check it before publishing."""
import os
import shutil
import sys
import tempfile
from pathlib import Path

from . import formats, manifest
from .config import STATE, die
from .targets import default_slug
from .targets.file import ours

MARK = '# Bundled by viz bundle'


def cmd_bundle(args):
    path = Path(args.page).expanduser()
    if not path.exists():
        die(f'no such page: {args.page}')
    try:
        page = manifest.locate(path)
    except ValueError as error:
        die(str(error))
    fmt = args.format or page.format
    out = Path(args.out).expanduser().absolute() if args.out else STATE / 'bundles' / default_slug(page)
    if page.folder and (out == page.folder or page.folder in out.parents):
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
    print(out)
    for note in report.notes:
        print(f'  note: {note}')
    for problem in report.problems:
        print(f'  problem: {problem}')
    if report.problems:
        print(f'{len(report.problems)} problem(s): viz publish refuses this page until they are fixed',
              file=sys.stderr)
        sys.exit(1)
