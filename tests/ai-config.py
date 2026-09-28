#!/usr/bin/env python3
"""Configuration preservation and recovery tests; no native CLI or network."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib'))
from config_files import dump_toml, equivalent


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)

    def put(self, name, text):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run_config(self, *args, ok=True):
        result = subprocess.run([str(ROOT / 'bin/ai-config'), '--home', str(self.home), *args], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.read_bytes(), p.stat().st_mtime_ns) for p in self.home.rglob('*') if p.is_file()}

    def test_preserves_unowned_values_and_updates_all_owned_keys(self):
        codex = self.put('.codex/config.toml', '''model_reasoning_effort = "low"
[projects."/a.b/#project"]
trust_level = "trusted"
[tui]
screen_reader_detection_done = true
[tui.keymap.global]
open_external_editor = "ctrl-x"
custom_binding = "ctrl-k"
''')
        claude = self.put('.claude/settings.json', '{"env":{"LOCAL_VALUE":"keep"},"permissions":{"defaultMode":"manual"},"enabledPlugins":{"unrelated":true}}')
        self.run_config()
        c = tomllib.loads(codex.read_text())
        self.assertEqual(c['model_reasoning_effort'], 'high')
        self.assertEqual(c['approval_policy'], 'on-request')
        # Provider-dependent keys are left to the provider's own configuration.
        self.assertNotIn('model_context_window', c)
        self.assertEqual(c['projects']['/a.b/#project']['trust_level'], 'trusted')
        self.assertTrue(c['tui']['screen_reader_detection_done'])
        self.assertEqual(c['tui']['keymap']['global'], {'open_external_editor': 'ctrl-e', 'custom_binding': 'ctrl-k'})
        d = json.loads(claude.read_text())
        self.assertEqual(d['env']['LOCAL_VALUE'], 'keep')
        self.assertEqual(d['permissions'], {'defaultMode': 'manual'})
        self.assertTrue(d['enabledPlugins']['unrelated'])
        self.assertTrue(list((self.home / '.codex/backups').glob('*/config.toml')))
        self.assertTrue(list((self.home / '.claude/backups').glob('*/settings.json')))
        self.assertFalse(list(self.home.rglob('.adapter-backups')))

    def test_repeat_and_check_are_byte_and_mtime_noops(self):
        self.run_config()
        before = self.snapshot()
        self.run_config()
        self.run_config('--check', '--plugins')
        self.assertEqual(before, self.snapshot())

    def test_invalid_second_document_prevents_all_writes(self):
        self.put('.codex/config.toml', 'model="local"\n')
        self.put('.claude/settings.json', '{broken')
        before = self.snapshot()
        self.run_config(ok=False)
        self.assertEqual(before, self.snapshot())

    def test_invalid_shape_and_symlink_preserved(self):
        path = self.put('.claude/settings.json', '{"env": []}')
        before = self.snapshot()
        self.run_config('claude', ok=False)
        self.assertEqual(before, self.snapshot())
        path.unlink()
        dest = self.put('external.json', '{}')
        path.symlink_to(dest)
        self.run_config('claude', ok=False)
        self.assertEqual(dest.read_text(), '{}')

    def test_dry_run_and_drift(self):
        self.run_config('--dry-run')
        self.assertEqual(list(self.home.iterdir()), [])
        self.run_config()
        self.put('.claude/statusline.sh', 'local change')
        before = self.snapshot()
        self.run_config('--check', ok=False)
        self.assertEqual(before, self.snapshot())

    def test_toml_types_round_trip(self):
        data = tomllib.loads('''title = "escaped \\\"text\\\""
stamp = 1979-05-27T07:32:00Z
day = 1979-05-27
clock = 07:32:00
special = nan
infinity = -inf
[[hooks.commands]]
command = "first"
[[hooks.commands]]
command = "second"
["quoted.table"]
"key.with.dots" = { nested = [1, 2, 3] }
''')
        data['emoji 🔧'] = 'control \x7f and 🔧'
        self.assertTrue(equivalent(data, tomllib.loads(dump_toml(data))))


if __name__ == '__main__':
    unittest.main(verbosity=2)
