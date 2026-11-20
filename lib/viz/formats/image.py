"""Images: pass-through. An SVG is also checked, like html, for anything it loads from outside."""
import shutil
from pathlib import Path

from . import Report, html

NAMES = ('svg', 'png', 'jpg', 'gif', 'webp')
EXPORTS = {}


def bundle(page, out, policy, include=(), exclude=()):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    name = page.entry.name
    shutil.copy2(page.entry, out / name)
    report = Report(entry=name, format=page.format, files=[name])
    if page.format == 'svg':
        checker = html.Bundler(out, policy)
        checker.outside(name, (out / name).read_text(errors='surrogateescape'))
        report.problems = checker.problems
    return report
