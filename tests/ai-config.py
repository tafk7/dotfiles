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

    def run_config(self, *args, ok=True, env=None):
        result = subprocess.run([str(ROOT / 'bin/ai-config'), '--home', str(self.home), *args], capture_output=True, text=True, env=env)
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

    def test_claude_fullscreen_leaves_mouse_env_local(self):
        # Mouse capture is unmanaged: the overlay merges, so a live value stays.
        claude = self.put('.claude/settings.json', '{"tui":"default","env":{"CLAUDE_CODE_DISABLE_MOUSE":"1","LOCAL_VALUE":"keep"}}')
        self.run_config('claude')
        d = json.loads(claude.read_text())
        self.assertEqual(d['tui'], 'fullscreen')
        self.assertEqual(d['env']['CLAUDE_CODE_DISABLE_MOUSE'], '1')
        self.assertEqual(d['env']['LOCAL_VALUE'], 'keep')
        self.assertEqual((self.home / '.claude/keybindings.json').read_bytes(),
                         (ROOT / 'configs/ai/claude/keybindings.json').read_bytes())

    def test_opencode_preferences_leave_providers_and_models_alone(self):
        path = self.put('.config/opencode/opencode.json',
                        '{"autoupdate":true,"model":"gw/big","provider":{"gw":{"models":{"big":{}}}}}')
        self.run_config('opencode')
        data = json.loads(path.read_text())
        self.assertEqual(data['autoupdate'], 'notify')
        self.assertEqual(data['share'], 'disabled')
        self.assertEqual(data['model'], 'gw/big')
        self.assertEqual(data['provider'], {'gw': {'models': {'big': {}}}})
        self.assertTrue(list((self.home / '.config/opencode/backups').glob('*/opencode.json')))

    def test_opencode_native_preferences_follow_verified_v2(self):
        path = self.put('.config/opencode/opencode.json', '{"autoupdate":true,"update":"auto","providers":{"mine":{}}}')
        cli = self.put('.local/bin/opencode', '#!/bin/sh\necho "opencode v2.0.22"\n')
        cli.chmod(0o755)
        self.run_config('opencode')
        config = json.loads(path.read_text())
        self.assertEqual(config['update'], 'notify')
        self.assertNotIn('autoupdate', config)
        self.assertEqual(config['providers'], {'mine': {}})
        before = self.snapshot()
        self.run_config('opencode')
        self.run_config('opencode', '--check')
        self.assertEqual(before, self.snapshot())

    def test_opencode_v2_keybinds_merge_into_cli_json(self):
        cli_json = self.put('.config/opencode/cli.json', '{"theme":{"name":"mine"},"keybinds":{"messages.copy":"<leader>w"}}')
        self.run_config('opencode')
        self.assertEqual(json.loads(cli_json.read_text())['keybinds'], {'messages.copy': '<leader>w'})
        cli = self.put('.local/bin/opencode', '#!/bin/sh\necho "opencode v2.0.22"\n')
        cli.chmod(0o755)
        self.run_config('opencode')
        data = json.loads(cli_json.read_text())
        self.assertEqual(data['theme'], {'name': 'mine'})
        self.assertEqual(data['keybinds']['messages.copy'], '<leader>w')
        self.assertTrue(data['keybinds']['session.first'].startswith('ctrl+home,'))
        self.assertTrue(data['keybinds']['session.last'].startswith('ctrl+end,'))
        self.run_config('opencode', '--check')

    def test_mod_plugins_require_the_claude_floor(self):
        import shutil
        source = ROOT / 'plugins/agent-badge-claude'
        version = json.loads((source / '.claude-plugin/plugin.json').read_text())['version']
        cache = self.home / '.claude/plugins/cache/tafk7/agent-badge' / version
        shutil.copytree(source, cache, ignore=shutil.ignore_patterns('types', '__pycache__'))
        self.put('.claude/plugins/installed_plugins.json', json.dumps({'plugins': {'agent-badge@tafk7': [
            {'scope': 'user', 'version': version, 'installPath': str(cache)}]}}))
        self.run_config('claude')
        settings = self.home / '.claude/settings.json'
        data = json.loads(settings.read_text())
        data.setdefault('enabledPlugins', {})['agent-badge@tafk7'] = True
        settings.write_text(json.dumps(data))

        def with_claude(reported):
            bin_dir = self.home / 'bin'
            bin_dir.mkdir(exist_ok=True)
            stub = bin_dir / 'claude'
            stub.write_text(f'#!/bin/sh\necho "{reported} (Claude Code)"\n')
            stub.chmod(0o755)
            return {**os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}'}

        old = self.run_config('claude', '--check', '--plugins', ok=False, env=with_claude('2.1.286'))
        self.assertIn('below the 2.1.287 floor', old.stdout)
        new = self.run_config('claude', '--check', '--plugins', env=with_claude('2.1.287'))
        self.assertIn('meets the 2.1.287 floor', new.stdout)

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

    def test_retired_keys_are_removed_only_when_unedited(self):
        self.run_config()
        record_path = self.home / '.local/state/dotfiles/ai/claude.json'
        record = json.loads(record_path.read_text())
        claude = self.home / '.claude/settings.json'
        entry = record['files'][str(claude)]
        # Keys a previous checkout applied and this one no longer ships.
        entry['applied'] += [[['env', 'OLD_DOTFILES'], '1'], [['oldTable', 'nested'], 'v'], [['edited'], 'a']]
        record_path.write_text(json.dumps(record))
        data = json.loads(claude.read_text())
        data['env']['OLD_DOTFILES'] = '1'
        data['oldTable'] = {'nested': 'v'}
        data['edited'] = 'b'
        data['unrelated'] = {'keep': True}
        claude.write_text(json.dumps(data))

        result = self.run_config('claude', '--check', ok=False)
        self.assertIn('CHECK: env.OLD_DOTFILES left the portable settings', result.stdout)
        before = claude.read_bytes()
        result = self.run_config('claude', '--dry-run')
        self.assertIn('would remove retired key oldTable.nested', result.stdout)
        self.assertEqual(claude.read_bytes(), before)

        result = self.run_config('claude')
        data = json.loads(claude.read_text())
        self.assertNotIn('OLD_DOTFILES', data['env'])
        self.assertNotIn('oldTable', data, 'a table left empty by the removal was kept')
        self.assertEqual(data['edited'], 'b')
        self.assertEqual(data['unrelated'], {'keep': True})
        self.assertIn('kept (edited since dotfiles wrote it): edited', result.stdout)
        # The edited key is reported once, and the result is converged.
        result = self.run_config('claude')
        self.assertNotIn('kept (edited', result.stdout)
        self.run_config('claude', '--check')
        conflicts = json.loads(record_path.read_text())['files'][str(claude)]['conflicts']
        self.assertEqual(conflicts, [['edited']])

    def test_retired_toml_keys_are_removed(self):
        self.run_config('codex')
        record_path = self.home / '.local/state/dotfiles/ai/codex.json'
        record = json.loads(record_path.read_text())
        codex = self.home / '.codex/config.toml'
        record['files'][str(codex)]['applied'].append([['old_codex_key'], 'x'])
        record_path.write_text(json.dumps(record))
        codex.write_text('old_codex_key = "x"\n' + codex.read_text())
        self.assertEqual(tomllib.loads(codex.read_text())['old_codex_key'], 'x')
        self.run_config('codex')
        self.assertNotIn('old_codex_key', tomllib.loads(codex.read_text()))

    def test_retired_files_are_removed_only_when_unmodified(self):
        retired = json.loads((ROOT / 'configs/ai/retired.json').read_text())['claude']
        clean = self.put('.claude/skills/viz/SKILL.md', 'x')
        kept = self.put('.claude/skills/viz-edited/SKILL.md', 'locally edited')
        import hashlib
        self.assertIn('skills/viz/SKILL.md', retired)
        sys.path.insert(0, str(ROOT / 'lib'))
        import ai_preferences
        digest = hashlib.sha256(b'x').hexdigest()
        self.assertTrue(ai_preferences.retire(clean, digest, self.home / '.claude/backups', True))
        self.assertTrue(clean.exists())
        ai_preferences.retire(clean, digest, self.home / '.claude/backups', False)
        self.assertFalse(clean.exists())
        self.assertEqual(len(list((self.home / '.claude/backups').rglob('SKILL.md'))), 1)
        ai_preferences.retire(kept, retired['skills/viz/SKILL.md'], self.home / '.claude/backups', False)
        self.assertTrue(kept.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
