"""pdf: pass-through, with one check: the file is a PDF with pages."""
import re
import shutil
from pathlib import Path

from . import Problem, Report

NAME = 'pdf'
SUFFIXES = ('.pdf',)
PAGE = re.compile(rb'/Type\s*/Page(?!s)')
EXPORTS = {}


def problems(path):
    data = Path(path).read_bytes()
    if not data.startswith(b'%PDF-'):
        return [Problem(Path(path).name, 'is not a PDF (it does not start with %PDF-)')]
    if not PAGE.search(data):
        return [Problem(Path(path).name, 'has no pages viz can find')]
    return []


def bundle(page, out, policy, include=(), exclude=()):
    Path(out).mkdir(parents=True, exist_ok=True)
    shutil.copy2(page.entry, Path(out) / page.entry.name)
    return Report(entry=page.entry.name, format=NAME, files=[page.entry.name],
                  problems=problems(Path(out) / page.entry.name))
