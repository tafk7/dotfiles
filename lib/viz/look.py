"""Take the one look at a page before publishing it: screenshots in light and dark, plus what broke.

    viz look PAGE [options]     (which runs this file under uv with a pinned Playwright)

Not imported by the viz CLI: it needs Playwright, which only exists in the environment uv makes for it.

Writes PNGs to PAGE's directory under .shots/ (hidden, so viz neither lists nor serves them) and
prints their paths, then one line per problem: script errors, files that failed to load, hosts
the page needs the network for, and a body wider than the viewport (sideways scroll).

The page is loaded from http://page.invalid/, answered from disk without opening any port, so
fetch() of a data file and ../ links work as they do under viz. Files outside --root are 404.

Options:
    --out PREFIX       PNG path prefix (default: PAGE_DIR/.shots/PAGE_STEM)
    --root DIR         directory served as the site root (default: PAGE's directory)
    --theme T          light, dark or both (default both); sets prefers-color-scheme and
                       data-theme on <html>, so pages with or without a theme toggle follow
    --width N          viewport width (default 1280)
    --phone            also shoot at 390 px wide, light only
    --full             the whole page instead of the first screen (cut at 6000 px)
    --selector CSS     only the first element matching CSS (a figure, say)
    --ready CSS        wait (up to 20 s) for an element matching CSS, for pages that build
                       themselves after the network goes quiet (an app with a loading screen)
    --js CODE          run CODE after load (open a panel, pick a tab) before the shot
    --wait MS          extra wait after load (default 300)
    --offline          refuse every request that is not to the page itself (a bundle's look)
    --pdf FILE         print the page to FILE (print CSS, light theme) instead of shooting it
    --paper SIZE       the pdf's paper: A4 (default) or Letter
"""

import argparse
import glob
import mimetypes
import os
import re
import sys
import urllib.parse
from pathlib import Path

from playwright.sync_api import Error, sync_playwright

ORIGIN = "http://page.invalid"
FONT_HOSTS = ("fonts.googleapis.com", "fonts.gstatic.com")
MAX_FULL = 6000


def build(path):
    """The Playwright build number in a cached browser's path (chromium-1248/... is 1248)."""
    match = re.search(r"-(\d+)/", path)
    return int(match.group(1)) if match else 0


def launch(p):
    """Chromium from this Playwright, else the newest one already in the Playwright cache."""
    try:
        return p.chromium.launch()
    except Error as first:
        cache = os.path.expanduser("~/.cache/ms-playwright")
        found = sorted(
            glob.glob(f"{cache}/chromium_headless_shell-*/*/chrome-headless-shell")
            + glob.glob(f"{cache}/chromium-*/chrome-linux*/chrome"),
            key=build,
        )
        if not found:
            sys.exit(
                "viz look: no Chromium for Playwright. It needs a one-time download (about 150 MB) with\n"
                "    uv run --no-project --with playwright playwright install chromium-headless-shell\n"
                "Ask the user before running it.\n" + str(first).splitlines()[0]
            )
        return p.chromium.launch(executable_path=found[-1])


def serve_from(root):
    def handle(route):
        rel = urllib.parse.unquote(
            urllib.parse.urlsplit(route.request.url).path
        ).lstrip("/")
        path = (root / rel).resolve()
        if path.is_dir():
            path = path / "index.html"
        if (path != root and root not in path.parents) or not path.is_file():
            return route.fulfill(status=404, body="not found")
        ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        route.fulfill(status=200, body=path.read_bytes(), content_type=ctype)

    return handle


def open_page(browser, url, root, theme, width, args, problems, notes):
    page = browser.new_page(
        viewport={"width": width, "height": 900},
        device_scale_factor=1 if args.full else 2,
        color_scheme=theme,
    )
    if args.offline:
        page.route("**/*", lambda route: route.abort("blockedbyclient"))
    page.route(f"{ORIGIN}/**", serve_from(root))
    page.on("pageerror", lambda e: problems.add(f"script error: {e}"))
    page.on(
        "console",
        lambda m: (
            m.type == "error"
            and not m.text.startswith("Failed to load resource")
            and problems.add(f"console error: {m.text}")
        ),
    )

    def on_response(r):
        if r.status >= 400:
            problems.add(
                f"failed to load ({r.status}): {r.url.replace(ORIGIN + '/', '')}"
            )

    page.on("response", on_response)
    page.on(
        "requestfailed",
        lambda r: problems.add(f"failed to load: {r.url} ({r.failure})"),
    )

    def on_request(r):
        host = urllib.parse.urlsplit(r.url).hostname
        if not host or host == "page.invalid" or not r.url.startswith("http"):
            return
        if args.offline:
            problems.add(
                f"needs the network: {host} (blocked: a bundle must load nothing from outside)"
            )
        elif host in FONT_HOSTS:
            notes.add(
                "web fonts come from the network; offline, the fallback stack shows"
            )
        else:
            problems.add(f"needs the network: {host}")

    page.on("request", on_request)

    try:
        page.goto(url, wait_until="networkidle", timeout=20000)
    except Error as e:
        problems.add(f"load did not settle: {str(e).splitlines()[0]}")
    page.evaluate(f"document.documentElement.dataset.theme = '{theme}'")
    if args.ready:
        try:
            page.wait_for_selector(args.ready, timeout=20000)
        except Error:
            problems.add(f"nothing matched --ready {args.ready} within 20 s")
    page.evaluate("document.fonts && document.fonts.ready")
    if args.js:
        page.evaluate(args.js)
    page.wait_for_timeout(args.wait)
    return page


def shoot(browser, url, root, out, theme, width, args, problems, notes):
    page = open_page(browser, url, root, theme, width, args, problems, notes)

    wide = page.evaluate("document.documentElement.scrollWidth - innerWidth")
    if wide > 1:
        problems.add(
            f"sideways scroll at {width} px: the page is {wide} px wider than the viewport"
        )
    if args.selector:
        target = page.locator(args.selector).first
        if target.count() == 0:
            problems.add(f"no element matches {args.selector}")
            target = None
    else:
        target = None
    if target is not None:
        target.screenshot(path=out)
    elif args.full:
        height = page.evaluate("document.documentElement.scrollHeight")
        if height > MAX_FULL:
            notes.add(
                f"the page is {height} px tall; the full shot stops at {MAX_FULL}"
            )
        page.screenshot(
            path=out,
            full_page=True,
            clip={"x": 0, "y": 0, "width": width, "height": min(height, MAX_FULL)},
        )
    else:
        page.screenshot(path=out)
    page.close()
    print(out)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("page")
    ap.add_argument("--out")
    ap.add_argument("--root")
    ap.add_argument("--theme", choices=("light", "dark", "both"), default="both")
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--phone", action="store_true")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--selector")
    ap.add_argument("--ready")
    ap.add_argument("--js")
    ap.add_argument("--wait", type=int, default=300)
    ap.add_argument("--offline", action="store_true")
    ap.add_argument("--pdf")
    ap.add_argument("--paper", choices=("A4", "Letter"), default="A4")
    args = ap.parse_args()

    page = Path(args.page).expanduser().resolve()
    if not page.is_file():
        sys.exit(f"viz look: no such file: {args.page}")
    root = Path(args.root).expanduser().resolve() if args.root else page.parent
    if root not in page.parents:
        sys.exit(f"viz look: {page} is not under --root {root}")
    prefix = (
        Path(args.out).expanduser() if args.out else page.parent / ".shots" / page.stem
    )
    if not args.pdf:
        prefix.parent.mkdir(parents=True, exist_ok=True)
    url = f"{ORIGIN}/" + urllib.parse.quote(page.relative_to(root).as_posix())

    problems, notes = set(), set()
    themes = ("light", "dark") if args.theme == "both" else (args.theme,)
    with sync_playwright() as p:
        browser = launch(p)
        if args.pdf:
            page = open_page(
                browser, url, root, "light", args.width, args, problems, notes
            )
            page.pdf(path=args.pdf, format=args.paper, print_background=True)
            page.close()
            browser.close()
            print(args.pdf)
            for line in sorted(problems):
                print("  problem: " + line)
            return
        for theme in themes:
            shoot(
                browser,
                url,
                root,
                f"{prefix}-{theme}.png",
                theme,
                args.width,
                args,
                problems,
                notes,
            )
        if args.phone:
            shoot(
                browser,
                url,
                root,
                f"{prefix}-phone.png",
                "light",
                390,
                args,
                problems,
                notes,
            )
        browser.close()
    for line in sorted(problems):
        print("  problem: " + line)
    if not problems:
        print("  no script errors, failed loads, network needs or sideways scroll")
    for line in sorted(notes):
        print("  note: " + line)


if __name__ == "__main__":
    main()
