#!/usr/bin/env python3
"""Reconcile portable AI preferences and assets without installing binaries."""
import argparse
from copy import deepcopy
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'lib'))
from config_files import backup, check_target, dump_toml, equivalent, leaves, load_json, merge, retire_leaves, write_file

TOML_HEADER = '# Portable keys are managed by dotfiles/bin/ai-config; other values are retained.\n'


def record_path(component, home):
    """Where the leaves last applied to each settings document are recorded."""
    if home != Path.home():
        base = home / '.local/state/dotfiles'
    elif os.environ.get('DOTFILES_STATE_DIR'):
        base = Path(os.environ['DOTFILES_STATE_DIR'])
    else:
        base = Path(os.environ.get('XDG_STATE_HOME', home / '.local/state')) / 'dotfiles'
    return base / 'ai' / f'{component}.json'


def load_record(component, home):
    path = record_path(component, home)
    record = load_json(path) if path.exists() else {}
    files = record.get('files', {})
    if not isinstance(files, dict):
        raise ValueError(f'Invalid AI settings record: {path}')
    return files


def released(component, target):
    """Keys dotfiles stopped managing in TARGET and left to the machine
    (configs/ai/released.json): forgotten rather than retired, so they keep
    their values."""
    listed = load_json(ROOT / 'configs/ai/released.json').get(component, {}).get(target.name, [])
    return {tuple(path) for path in listed}


def _read(path):
    return tomllib.loads(path.read_text()) if path.suffix == '.toml' else load_json(path)


def portable_sources(source):
    """SOURCE's enforced keys, and its defaults: the .defaults sibling, if any
    (configs/codex.toml and configs/codex.defaults.toml)."""
    sibling = source.with_name(f'{source.stem}.defaults{source.suffix}')
    return _read(source), (_read(sibling) if sibling.exists() else {})


MISSING = object()


def _leaf(data, path):
    """('set', value), ('absent', None), or ('blocked', None) when something
    other than a table is in the way."""
    node = data
    for key in path[:-1]:
        if key not in node:
            return 'absent', None
        node = node[key]
        if not isinstance(node, dict):
            return 'blocked', None
    return ('set', node[path[-1]]) if path[-1] in node else ('absent', None)


def _set_leaf(data, path, value):
    node = data
    for key in path[:-1]:
        node = node.setdefault(key, {})
    node[path[-1]] = deepcopy(value)


class Settings:
    """One settings document: its new text, and what retirement found.

    overlay holds the enforced keys, put back on every run. defaults hold keys
    a machine owns once it changes them: a default is written where the key is
    absent and was never written, and updated while the document still holds
    the value dotfiles last wrote (or, with nothing recorded, the default
    itself); otherwise it is left alone. An enforced key that becomes a default
    carries its recorded value over, so it is handed over rather than reset."""
    def __init__(self, target, base, overlay, previous, fmt, original=None, released=(), defaults=None):
        """base is the document to merge into; original, what the target holds
        now (default: base), keeps the bytes when nothing changes; released
        paths are dropped from the record instead of retired."""
        original = base if original is None else original
        released, defaults = set(released), defaults or {}
        recorded = {tuple(k): v for k, v in previous.get('applied', []) if tuple(k) not in released}
        written = {tuple(k): v for k, v in previous.get('defaults', []) if tuple(k) not in released}
        self.target, self.overlay = target, overlay
        self.conflicts_before = {tuple(k) for k in previous.get('conflicts', [])} - released
        # Keys that left both the overlay and the defaults are retired; a key
        # moving from one to the other is not.
        portable, enforced = merge(defaults, overlay), leaves(overlay)
        retired, self.removed, self.conflicts = retire_leaves(base, recorded, portable)
        retired, _, _ = retire_leaves(retired, written, portable)
        self.written = {}
        for path, value in leaves(defaults).items():
            if any(path[:i] in enforced for i in range(1, len(path) + 1)):
                continue
            last = written.get(path, recorded.get(path, MISSING))
            state, live = _leaf(retired, path)
            if state == 'blocked':
                continue
            owned = (last is MISSING and (state == 'absent' or equivalent(live, value))) \
                or (last is not MISSING and state == 'set' and equivalent(live, last))
            if owned:
                _set_leaf(retired, path, value)
                self.written[path] = value
            elif last is not MISSING:
                # The machine changed or removed it; remember what was written.
                self.written[path] = last
        data = merge(retired, overlay)
        if target.exists() and equivalent(data, original):
            self.text = target.read_text()
        elif fmt == 'toml':
            self.text = TOML_HEADER + dump_toml(data)
        else:
            self.text = json.dumps(data, indent=2) + '\n'

    def record(self):
        applied = leaves(self.overlay)
        conflicts = sorted(path for path in self.conflicts_before | set(self.conflicts) if path not in applied)
        return {'applied': [[list(path), value] for path, value in sorted(applied.items())],
                'defaults': [[list(path), value] for path, value in sorted(self.written.items())],
                'conflicts': [list(path) for path in conflicts]}


def json_settings(target, source, previous, released=()):
    overlay, defaults = portable_sources(source)
    return Settings(target, load_json(target), overlay, previous, 'json', released=released, defaults=defaults)


def desired(component, home, record=None):
    """The component's directory, its outputs (path, bytes, mode), and its
    settings documents (see Settings). Leaves a previous run applied and the
    portable sources no longer ship are retired (see retire_leaves)."""
    record = record or {}
    directory = home / ('.' + component)
    extra, settings = [], []
    if component == 'codex':
        directory = Path(os.environ.get('CODEX_HOME', directory)) if home == Path.home() else directory
        target = directory / 'config.toml'
        check_target(target)
        original = tomllib.loads(target.read_text()) if target.exists() else {}
        overlay, defaults = portable_sources(ROOT / 'configs/codex.toml')
        settings.append(Settings(target, original, overlay, record.get(str(target), {}), 'toml',
                                 released=released(component, target), defaults=defaults))
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
        overlay, defaults = portable_sources(source)
        if component == 'opencode':
            # Until a V2 binary is installed, keep the supported V1 spelling.
            # Configuration can be provisioned before installing any CLI.
            cli = (shutil.which('opencode') if home == Path.home() else None) or str(home / '.local/bin/opencode')
            try:
                version = subprocess.run([cli, '--version'], capture_output=True, text=True, timeout=15)
                v2 = version.returncode == 0 and re.search(r'\bv?2\.\d+\.\d+', version.stdout)
            except (OSError, subprocess.TimeoutExpired):
                v2 = False
            overlay = dict(overlay)
            base = dict(original)
            if v2:
                base.pop('autoupdate', None)
                if base.get('$schema') == 'https://opencode.ai/config.json':
                    base.pop('$schema')
                # V2's TUI settings (keybinds) live in cli.json, which opencode
                # also writes itself; merge into it like opencode.json.
                cli_target = directory / 'cli.json'
                check_target(cli_target)
                cli = json_settings(cli_target, ROOT / 'configs/opencode-cli.json', record.get(str(cli_target), {}),
                                    released(component, cli_target))
                extra.append((cli_target, cli.text.encode(), 0o600))
                settings.append(cli)
            else:
                overlay['autoupdate'] = overlay.pop('update')
                # Preserve any native value until V2 is available to own it.
            document = Settings(target, base, overlay, record.get(str(target), {}), 'json', original,
                                released(component, target), defaults)
        else:
            document = Settings(target, original, overlay, record.get(str(target), {}), 'json',
                                released=released(component, target), defaults=defaults)
        settings.insert(0, document)
    outputs = [(settings[0].target, settings[0].text.encode(), 0o600), *extra]
    assets = ROOT / 'configs/ai' / component
    for source in sorted(assets.rglob('*')):
        if source.is_file() and '__pycache__' not in source.parts:
            dest = directory / source.relative_to(assets)
            check_target(dest)
            outputs.append((dest, source.read_bytes(), 0o600))
    return directory, outputs, settings


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
    parser.add_argument('--check-plugin', action='store_true', help='check only the enabled badge cache (claude or codex)')
    args = parser.parse_args()
    if args.check_plugin:
        if args.component not in ('claude', 'codex'):
            parser.error('--check-plugin needs claude or codex')
        return 0 if check_plugin(args.component, desired(args.component, args.home)[0]) else 1
    # Validate every document and target before writing any of them.
    plans = []
    for c in (['codex', 'claude', 'opencode'] if args.component == 'all' else [args.component]):
        record = load_record(c, args.home)
        plans.append((c, record, *desired(c, args.home, record)))
    ok = True
    for component, record, directory, outputs, settings in plans:
        for document in settings:
            for path in document.removed:
                key = '.'.join(path)
                if args.check:
                    print(f'CHECK: {key} left the portable settings but is still set in {document.target}')
                else:
                    print(f'{"would remove" if args.dry_run else "removed"} retired key {key} from {document.target}')
            if not args.check:
                for path in sorted(set(document.conflicts) - document.conflicts_before):
                    print(f'kept (edited since dotfiles wrote it): {".".join(path)} in {document.target}')
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
        if not args.check and not args.dry_run:
            updated = dict(record)
            updated.update({str(d.target): d.record() for d in settings})
            if updated != record:
                text = json.dumps({'schema': 1, 'files': updated}, indent=2, sort_keys=True, default=str) + '\n'
                path = record_path(component, args.home)
                path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
                fd, staged = tempfile.mkstemp(dir=path.parent, prefix=path.name + '.')
                with os.fdopen(fd, 'w') as handle:
                    handle.write(text)
                os.replace(staged, path)
        if args.check and args.plugins and component != 'opencode':
            ok = check_plugin(component, directory) and ok
        if component == 'claude':
            env = load_json(ROOT / 'configs/claude-settings.json').get('env', {})
            print('info: Claude nonessential traffic disabled; updates are explicit (bin/ai-update claude).'
                  if env.get('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC') == '1' else 'info: Claude updater follows its runtime environment.')
        if component == 'opencode':
            print('info: opencode notifies about updates; install them with bin/ai-update opencode.'
                  if load_json(ROOT / 'configs/opencode.json').get('update') == 'notify' else 'info: opencode updater follows its configuration.')
    return 0 if ok else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
