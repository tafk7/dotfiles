#!/usr/bin/env python3
"""Check local Markdown link targets in current documentation (history excluded)."""
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

root = Path(__file__).resolve().parents[1]
paths = [root / "README.md", *root.glob("docs/*.md"), *root.glob("plugins/*/README.md")]
failures = []
for path in paths:
    for target in re.findall(r"\[[^\]]*\]\(([^)\s]+)\)", path.read_text()):
        parsed = urlsplit(target)
        if parsed.scheme or not parsed.path:
            continue
        if not (path.parent / unquote(parsed.path)).exists():
            failures.append(f"{path.relative_to(root)}: missing {target}")
if failures:
    raise SystemExit("\n".join(failures))
print("documentation: ok")
