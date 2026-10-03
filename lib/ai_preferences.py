#!/usr/bin/env python3
"""Reconcile portable AI preferences and assets without installing binaries."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib'))
from config_files import backup, check_target, equivalent, load_json, merge, reconcile_toml, write_file


def desired(component, home):
    directory = home / ('.' + component)
    if component == 'codex':
        directory = Path(os.environ.get('CODEX_HOME', directory)) if home == Path.home() else directory
        target = directory / 'config.toml'
        check_target(target)
        original = target.read_text() if target.exists() else ''
        overlay = tomllib.loads((ROOT / 'configs/codex.toml').read_text())
        text = reconcile_toml(original, overlay, header='# Portable keys are managed by dotfiles/bin/ai-config; other values are retained.\n')
    else:
        if component == 'opencode':
            config_home = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config')) if home == Path.home() else home / '.config'
            directory = config_home / 'opencode'
            target = directory / 'opencode.json'
            source = ROOT / 'configs/opencode.json'
        else:
            directory = Path(os.environ.get('CLAUDE_CONFIG_DIR', directory)) if home == Path.home() else directory
            target = directory / 'settings.json'
            source = ROOT / 'configs/claude-settings.json'
        original = load_json(target)
        data = merge(original, load_json(source))
        text = target.read_text() if target.exists() and equivalent(data, original) else json.dumps(data, indent=2) + '\n'
    outputs = [(target, text.encode(), 0o600)]
    assets = ROOT / 'configs/ai' / component
    for source in sorted(assets.rglob('*')):
        if source.is_file() and '__pycache__' not in source.parts:
            dest = directory / source.relative_to(assets)
            check_target(dest)
            outputs.append((dest, source.read_bytes(), 0o600))
    return directory, outputs


MODS_FLOOR = (2, 1, 287)


def retired(component, directory):
    """Files dotfiles once wrote that another owner now ships: {path, sha256}."""
    listed = load_json(ROOT / 'configs/ai/retired.json').get(component, {})
    return [(directory / rel, digest) for rel, digest in sorted(listed.items())]


def retire(path, digest, backup_dir, dry_run):
    """Remove a retired file only if it still holds what dotfiles last wrote."""
    check_target(path)
    if not path.is_file():
        return True
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        print(f'kept (edited since dotfiles wrote it): {path}')
        return True
    if dry_run:
        print(f'would remove retired: {path} (backups: {backup_dir})')
        return True
    print(f'backup: {backup(path, backup_dir)}')
    path.unlink()
    try:
        path.parent.rmdir()
    except OSError:
        pass
    print(f'removed retired: {path}')
    return True


def check_mods_floor(source):
    # A plugin whose hooks.json declares `modules` needs a Claude Code that loads mods.
    hooks = source / 'hooks/hooks.json'
    if not hooks.is_file() or not load_json(hooks).get('modules'):
        return True
    floor = '.'.join(map(str, MODS_FLOOR))
    claude = shutil.which('claude')
    found = None
    if claude:
        out = subprocess.run([claude, '--version'], capture_output=True, text=True).stdout
        match = re.search(r'(\d+)\.(\d+)\.(\d+)', out)
        found = tuple(map(int, match.groups())) if match else None
    ok = found is not None and found >= MODS_FLOOR
    shown = '.'.join(map(str, found)) if found else 'not found'
    print(f'{"ok" if ok else "CHECK"}: claude {shown} {"meets" if ok else "is below"} the {floor} floor for mod plugins')
    return ok


def check_plugin(component, directory):
    config = tomllib.loads((directory / 'config.toml').read_text()) if component == 'codex' else load_json(directory / 'settings.json')
    enabled = config.get('plugins', {}).get('agent-badge@tafk7', {}).get('enabled', False) if component == 'codex' else config.get('enabledPlugins', {}).get('agent-badge@tafk7', False)
    if not enabled:
        print(f'info: {component} badge plugin not enabled')
        return True
    source = ROOT / 'plugins' / ('agent-badge-' + component)
    floor_ok = component != 'claude' or check_mods_floor(source)
    manifest = '.codex-plugin/plugin.json' if component == 'codex' else '.claude-plugin/plugin.json'
    version = load_json(source / manifest)['version']
    cache = directory / 'plugins/cache/tafk7/agent-badge' / version
    if component == 'claude':
        installed = load_json(directory / 'plugins/installed_plugins.json')
        entries = installed.get('plugins', {}).get('agent-badge@tafk7', [])
        entry = next((e for e in entries if e.get('scope') == 'user'), None)
        if not entry or entry.get('version') != version:
            print(f'CHECK: {component} badge installed version differs from {version}')
            return False
        cache = Path(entry['installPath'])
    ok = all((cache / p.relative_to(source)).is_file() and (cache / p.relative_to(source)).read_bytes() == p.read_bytes()
             for p in source.rglob('*') if p.is_file() and '.claude-plugin/types' not in p.as_posix())
    print(f'{"ok" if ok else "CHECK"}: {component} badge cache matches source: {ok}')
    return ok and floor_ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('component', choices=['codex', 'claude', 'opencode', 'all'], nargs='?', default='all')
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--plugins', action='store_true', help='also check enabled badge caches with --check')
    args = parser.parse_args()
    # Validate every document and target before writing any of them.
    plans = [(c, *desired(c, args.home)) for c in (['codex', 'claude', 'opencode'] if args.component == 'all' else [args.component])]
    ok = True
    for component, directory, outputs in plans:
        for path, data, mode in outputs:
            if args.check:
                matches = path.is_file() and path.read_bytes() == data
                print(f'{"ok" if matches else "CHECK"}: {path}')
                ok = matches and ok
            else:
                write_file(path, data, directory / 'backups', args.dry_run, mode)
        for path, digest in retired(component, directory):
            if args.check:
                if path.is_file():
                    stale = hashlib.sha256(path.read_bytes()).hexdigest() == digest
                    print(f'{"CHECK" if stale else "kept"}: retired file present: {path}')
                    ok = (not stale) and ok
            else:
                retire(path, digest, directory / 'backups', args.dry_run)
        if args.check and args.plugins and component != 'opencode':
            ok = check_plugin(component, directory) and ok
        if component == 'claude':
            env = load_json(ROOT / 'configs/claude-settings.json').get('env', {})
            print('info: Claude nonessential traffic disabled; updates are explicit (bin/ai-update claude).'
                  if env.get('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC') == '1' else 'info: Claude updater follows its runtime environment.')
        if component == 'opencode':
            print('info: opencode notifies about updates; install them with bin/ai-update opencode.'
                  if load_json(ROOT / 'configs/opencode.json').get('autoupdate') == 'notify' else 'info: opencode updater follows its configuration.')
    return 0 if ok else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
