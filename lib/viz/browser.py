"""Running look.py, the one part of viz that needs a browser: under uv, with a pinned Playwright.

The CLI stays standard-library. uv makes Playwright's environment on first use; Playwright's Chromium is a
one-time download that look.py asks the user about rather than starting on its own.
"""
import shutil
import subprocess
import sys
from pathlib import Path

PLAYWRIGHT = '1.64.1'   # its Chromium is build 1248
LOOK = Path(__file__).resolve().with_name('look.py')


class BrowserError(Exception):
    pass


def command(args):
    uv = shutil.which('uv')
    if uv is None:
        raise BrowserError('viz look needs uv (https://docs.astral.sh/uv/), which runs Playwright for it')
    return [uv, 'run', '--quiet', '--no-project', '--with', f'playwright=={PLAYWRIGHT}', 'python', str(LOOK),
            *args]


def run(args, capture=False):
    """Run look.py with ARGS; its output goes to ours unless CAPTURE."""
    cmd = command(args)
    sys.stdout.flush()
    return subprocess.run(cmd, capture_output=capture, text=True, check=False,
                          stdin=subprocess.DEVNULL, stdout=None if capture else sys.stdout)
