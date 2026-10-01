#!/usr/bin/env python3
"""Reconcile portable AI preferences and assets without installing binaries."""
import argparse
import json
import os
from pathlib import Path
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib'))
from config_files import check_target, equivalent, load_json, merge, reconcile_toml, write_file


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
            outputs.append((dest, source.read_bytes(), 0o700 if os.access(source, os.X_OK) else 0o600))
    return directory, outputs


def check_plugin(component, directory):
    config = tomllib.loads((directory / 'config.toml').read_text()) if component == 'codex' else load_json(directory / 'settings.json')
    enabled = config.get('plugins', {}).get('agent-badge@tafk7', {}).get('enabled', False) if component == 'codex' else config.get('enabledPlugins', {}).get('agent-badge@tafk7', False)
    if not enabled:
        print(f'info: {component} badge plugin not enabled')
        return True
    source = ROOT / 'plugins' / ('agent-badge-' + component)
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
             for p in source.rglob('*') if p.is_file())
    print(f'{"ok" if ok else "CHECK"}: {component} badge cache matches source: {ok}')
    return ok


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
