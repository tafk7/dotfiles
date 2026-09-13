#!/usr/bin/env python3
"""Contrast checks for informational theme roles and light ANSI palettes."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


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


def parse_palette(path: Path):
    text = path.read_text()
    values = dict(re.findall(r"^(THEME_[A-Z0-9_]+)='(#[0-9A-Fa-f]{6})'", text, re.M))
    ansi_match = re.search(r"THEME_ANSI=\((.*?)\)", text, re.S)
    ansi = re.findall(r"#[0-9A-Fa-f]{6}", ansi_match.group(1)) if ansi_match else []
    return values, ansi


failures = []
for path in sorted((ROOT / "themes").glob("*/palette.sh")):
    theme = path.parent.name
    values, ansi = parse_palette(path)
    bg = values["THEME_BG_HEX"]
    if len(ansi) != 16:
        failures.append(f"{theme} ANSI palette has {len(ansi)} entries")
    for role in ("THEME_FG_HEX", "THEME_SECONDARY_HEX"):
        ratio = contrast(values[role], bg)
        if ratio < 4.5:
            failures.append(f"{theme} {role} {ratio:.2f}:1")
    for label, foreground, background in (
        ("selected", values["THEME_FG_HEX"], values["THEME_SURFACE_HEX"]),
        ("search", values["THEME_BG_HEX"], values["THEME_YELLOW_HEX"]),
        ("active-search", values["THEME_BG_HEX"], values["THEME_ACCENT_HEX"]),
    ):
        ratio = contrast(foreground, background)
        if ratio < 4.5:
            failures.append(f"{theme} {label} {ratio:.2f}:1")
    if luminance(bg) > 0.5:
        for index, color in enumerate(ansi):
            ratio = contrast(color, bg)
            if ratio < 4.5:
                failures.append(f"{theme} ANSI {index} {color} {ratio:.2f}:1")

    # The same secondary role must feed the major informational surfaces.
    btop = (path.parent / "btop.theme").read_text()
    starship = (path.parent / "starship.palette.toml").read_text()
    if values["THEME_SECONDARY_HEX"].lower() not in btop.lower():
        failures.append(f"{theme} btop does not use secondary role")
    if values["THEME_SECONDARY_HEX"].lower() not in starship.lower():
        failures.append(f"{theme} Starship does not use secondary role")
    btop_roles = dict(re.findall(r'theme\[([^]]+)\]="(#[0-9A-Fa-f]{6})"', btop))
    if "selected_fg" in btop_roles and contrast(btop_roles["selected_fg"], btop_roles["selected_bg"]) < 4.5:
        failures.append(f"{theme} btop selected text is below 4.5:1")
    lazygit = (path.parent / "lazygit.yml").read_text()
    def yaml_color(key):
        match = re.search(rf"{key}:\s*(?:\n\s*-\s*)?\[?['\"](#[0-9A-Fa-f]{{6}})", lazygit)
        return match.group(1) if match else None
    lazy_fg = yaml_color("defaultFgColor")
    for key in ("selectedLineBgColor", "inactiveViewSelectedLineBgColor"):
        lazy_bg = yaml_color(key)
        if lazy_fg and lazy_bg and contrast(lazy_fg, lazy_bg) < 4.5:
            failures.append(f"{theme} lazygit {key} text is below 4.5:1")

if failures:
    print("theme contrast failures:", file=sys.stderr)
    print("\n".join(f"  {item}" for item in failures), file=sys.stderr)
    raise SystemExit(1)

print("theme-contrast: ok")
