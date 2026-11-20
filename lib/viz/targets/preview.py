"""The built-in `preview` target: the private browser, where every draft already is (`viz open`)."""
import argparse
from dataclasses import dataclass

from . import Target


@dataclass
class PreviewTarget(Target):
    name: str = 'preview'
    type: str = 'preview'
    description: str = 'The private browser where every draft already is; the same as viz open PAGE'
    audience: str = 'you, in your browser over the ssh forward'
    builtin = True
    records = False
    usage = 'viz publish PAGE --to preview   (viz open PAGE; nothing is copied or recorded)'

    def open(self, page, args):
        index = page.folder is not None and page.entry.name in ('index.html', 'index.htm')
        what = page.folder if index else page.entry
        if args.dry_run:
            print(f'would open {what} in the browser (viz open); nothing is copied or recorded')
            return
        from ..cli import (
            cmd_open,  # the CLI imports this package; the import waits until it is needed
        )
        cmd_open(argparse.Namespace(files=[str(what)], browser=True, vscode=False))
