#!/usr/bin/env python3
"""Structure and contrast checks for themes/*.sh palettes."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("BG", "FG", "SECONDARY", "SURFACE", "SURFACE_2", "BORDER", "ACCENT", "ACCENT_2", "RED", "YELLOW", "GREEN")


def rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255 for i in (0, 2, 4))


def luminance(value: str):
    channels = []
    for channel in rgb(value):
        channels.append(channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(a: str, b: str):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def blend(a: str, b: str, pct: int):
    """Same integer mix as bin/theme-switcher's blend()."""
    a, b = a.lstrip("#"), b.lstrip("#")
    return "#" + "".join(
        f"{(int(a[i:i + 2], 16) * pct + int(b[i:i + 2], 16) * (100 - pct)) // 100:02x}" for i in (0, 2, 4)
    )


def parse_palette(path: Path):
    text = path.read_text()
    values = dict(re.findall(r"^(THEME_[A-Z0-9_]+)='(#[0-9A-Fa-f]{6})'", text, re.M))
    meta = dict(re.findall(r'^(NAME|DESCRIPTION)="([^"]+)"', text, re.M))
    ansi_match = re.search(r"THEME_ANSI=\((.*?)\)", text, re.S)
    ansi = re.findall(r"#[0-9A-Fa-f]{6}", ansi_match.group(1)) if ansi_match else []
    return values, meta, ansi


failures = []
themes = sorted((ROOT / "themes").glob("*.sh"))
if not themes:
    failures.append("no themes found")
for path in themes:
    theme = path.stem
    values, meta, ansi = parse_palette(path)
    missing = [f"THEME_{role}_HEX" for role in ROLES if f"THEME_{role}_HEX" not in values]
    missing += [f"THEME_TINT_{n}" for n in (1, 2, 3) if f"THEME_TINT_{n}" not in values]
    missing += [key for key in ("NAME", "DESCRIPTION") if key not in meta]
    if not re.fullmatch(r"[a-z0-9-]+", theme):
        failures.append(f"{theme} file name must be lowercase letters, digits, and dashes")
    if missing:
        failures.append(f"{theme} missing {', '.join(missing)}")
        continue
    if len(ansi) != 16:
        failures.append(f"{theme} ANSI palette has {len(ansi)} entries")

    bg, fg = values["THEME_BG_HEX"], values["THEME_FG_HEX"]
    for role in ("THEME_FG_HEX", "THEME_SECONDARY_HEX"):
        ratio = contrast(values[role], bg)
        if ratio < 4.5:
            failures.append(f"{theme} {role} {ratio:.2f}:1")
    checks = [
        ("selected", fg, values["THEME_SURFACE_HEX"]),
        ("selection", fg, values["THEME_SURFACE_2_HEX"]),
        ("search", bg, values["THEME_YELLOW_HEX"]),
        ("active-search", bg, values["THEME_ACCENT_HEX"]),
    ]
    # Diff lines keep syntax colors on these backgrounds; normal text must stay readable.
    for label, color in (("added", "THEME_GREEN_HEX"), ("removed", "THEME_RED_HEX")):
        for pct in (14, 24):
            checks.append((f"{label}-{pct}", fg, blend(values[color], bg, pct)))
    for label, foreground, background in checks:
        ratio = contrast(foreground, background)
        if ratio < 4.5:
            failures.append(f"{theme} {label} {ratio:.2f}:1")
    if luminance(bg) > 0.5:
        for index, color in enumerate(ansi):
            ratio = contrast(color, bg)
            if ratio < 4.5:
                failures.append(f"{theme} ANSI {index} {color} {ratio:.2f}:1")

if failures:
    print("theme contrast failures:", file=sys.stderr)
    print("\n".join(f"  {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)

print("theme-contrast: ok")
