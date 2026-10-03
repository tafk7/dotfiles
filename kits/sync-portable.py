#!/usr/bin/env python3
"""Render the portable AI configuration into the ai-preferences sbx kit.

A sandbox gets none of the host's Claude or Codex state (docs/work.md). This
copies the explicitly portable subset of configs/ into kits/ai-preferences/,
which the kit's image carries and its install hook places in the agent's home:

  configs/claude-settings.json   the keys in SETTINGS_KEYS, as Claude Code's
                                 managed settings (/etc/claude-code), which the
                                 harness kit's own settings.json cannot clobber
  configs/ai/claude/             keybindings (content skills come from their owners' kits)
  configs/ai/codex/              the skills in CODEX_SKILLS

Left out, because they depend on the host or the provider: the model (a
gateway names its own), and the status line (a host script and jq).

Usage: kits/sync-portable.py            write the kit's generated files
       kits/sync-portable.py --check    exit 1 if they are stale (pre-commit)
"""

import json
import shutil
import sys
import tempfile
from filecmp import dircmp
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KIT = ROOT / "kits" / "ai-preferences"
SETTINGS_KEYS = (
    "attribution",
    "autoCompactEnabled",
    "effortLevel",
    "env",
    "skipWorkflowUsageWarning",
    "theme",
    "verbose",
)
CLAUDE_FILES = ("keybindings.json",)
CODEX_SKILLS = ("thread-handoff",)
GENERATED = ("home", "etc")


def render(out: Path) -> None:
    settings = json.loads((ROOT / "configs" / "claude-settings.json").read_text())
    managed = {key: settings[key] for key in SETTINGS_KEYS if key in settings}
    target = out / "etc" / "claude-code" / "managed-settings.json"
    target.parent.mkdir(parents=True)
    target.write_text(json.dumps(managed, indent=2, sort_keys=True) + "\n")

    claude, codex = ROOT / "configs" / "ai" / "claude", ROOT / "configs" / "ai" / "codex"
    home = out / "home"
    (home / ".claude").mkdir(parents=True)
    for name in CLAUDE_FILES:
        shutil.copy2(claude / name, home / ".claude" / name)
    for name in CODEX_SKILLS:
        shutil.copytree(codex / "skills" / name, home / ".codex" / "skills" / name)


def differs(left: Path, right: Path) -> bool:
    if left.exists() != right.exists():
        return True
    if not left.exists():
        return False
    comparison = dircmp(left, right)

    def walk(c) -> bool:
        if c.left_only or c.right_only or c.diff_files or c.funny_files:
            return True
        return any(walk(sub) for sub in c.subdirs.values())

    return walk(comparison)


def main(argv) -> int:
    check = argv == ["--check"]
    if argv not in ([], ["--check"]):
        print("\n".join(__doc__.strip().splitlines()[-2:]), file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory() as scratch:
        fresh = Path(scratch)
        render(fresh)
        stale = [name for name in GENERATED if differs(fresh / name, KIT / name)]
        if check:
            if stale:
                print(
                    "kits/ai-preferences is stale (%s); run kits/sync-portable.py"
                    % ", ".join(stale),
                    file=sys.stderr,
                )
                return 1
            return 0
        for name in GENERATED:
            shutil.rmtree(KIT / name, ignore_errors=True)
            shutil.copytree(fresh / name, KIT / name)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
