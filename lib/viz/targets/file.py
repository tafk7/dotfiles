"""The built-in `file` target: the portable form written to a path, to attach or copy by hand."""
import os
import shutil
from dataclasses import dataclass
from pathlib import Path

from .. import manifest
from . import Target, TargetError

MARK = '# Published by viz publish'   # the first line of every manifest viz publish writes


@dataclass
class FileTarget(Target):
    name: str = 'file'
    type: str = 'file'
    description: str = 'The portable form, written where --out says: to attach to a mail or a ticket'
    audience: str = 'whoever you hand the file to'
    builtin = True
    usage = 'viz publish PAGE --to file --out PATH   (a folder; a single FILE.pdf with --format pdf)'

    def place(self, job, last, reuse):
        out = job.out or (last.get('place') if reuse and last else None)
        if not out:
            raise TargetError('--to file needs --out PATH (a folder, or FILE.pdf for a pdf)')
        dest = Path(out).expanduser().absolute()
        again = bool(last) and Path(str(last.get('place', ''))).expanduser().absolute() == dest
        page = job.page
        if page.folder and (dest == page.folder or page.folder in dest.parents):
            raise TargetError(f'{dest} is inside the page itself; write it somewhere else')
        if manifest.format_of(dest) == job.format and job.format != 'html':
            if dest.is_dir():
                raise TargetError(f'{dest} is a folder; give the file path to write')
            if dest.exists() and not again:
                raise TargetError(f'{dest} exists and is not this page\'s earlier copy; remove it or pick another')
        else:
            if dest.suffix.lower() in ('.html', '.htm'):
                raise TargetError('an html page is published as a folder: give --out a folder path')
            if dest.exists() and not dest.is_dir():
                raise TargetError(f'{dest} exists and is not a folder')
            if dest.is_dir() and any(dest.iterdir()) and not ours(dest):
                raise TargetError(f'{dest} is a folder viz did not publish; give an empty or new folder')
        return str(dest), '', []

    def publish(self, job, bundle_dir, text):
        dest = Path(job.place)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if manifest.format_of(dest) == job.format and job.format != 'html':
            shutil.copy2(bundle_dir / job.report.entry, dest)
            Path(str(dest) + manifest.SIDECAR).write_text(text)
            return {}
        staged = dest.with_name(f'.{dest.name}.viz-{os.getpid()}')
        shutil.copytree(bundle_dir, staged)
        (staged / manifest.NAME).write_text(text)
        if dest.exists():
            shutil.rmtree(dest)
        staged.rename(dest)
        return {}


def ours(folder):
    """True for a folder viz publish or viz bundle wrote: its page.toml starts with their mark."""
    try:
        with open(folder / manifest.NAME) as f:
            return f.readline().startswith((MARK, '# Bundled by viz bundle'))
    except OSError:
        return False
