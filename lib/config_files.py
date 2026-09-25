"""Small, dependency-free configuration transactions (Python 3.11+).

TOML updates preserve parsed values, not formatting. A semantic no-op keeps the
original bytes. Always validate the complete result before replacing a file.
Callers must choose a backup directory; no adjacent backup files are created.
"""
from copy import deepcopy
from datetime import date, datetime, time
import json
import math
import os
import re
from pathlib import Path
import shutil
import tempfile
import tomllib


def check_target(path):
    path = Path(path)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f'Refusing non-regular configuration target: {path}')


def load_json(path):
    check_target(path)
    data = json.loads(Path(path).read_text()) if Path(path).exists() else {}
    if not isinstance(data, dict):
        raise ValueError(f'Expected a JSON object: {path}')
    return data


def merge(base, overlay):
    result = deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict):
            if key in result and not isinstance(result[key], dict):
                raise ValueError(f'Expected an object at configuration key {key}')
            result[key] = merge(result.get(key, {}), value)
        else:
            result[key] = deepcopy(value)
    return result


def toml_key(value):
    return value if re.fullmatch(r"[A-Za-z0-9_-]+", value) else json.dumps(value, ensure_ascii=False).replace("\x7f", "\\u007f")


def toml_value(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).replace("\x7f", "\\u007f")
    if isinstance(value, (datetime, date, time)):
        return value.isoformat()
    if isinstance(value, (int, float)):
        return str(value).lower()
    if isinstance(value, list):
        return '[' + ', '.join(toml_value(item) for item in value) + ']'
    if isinstance(value, dict):
        return '{ ' + ', '.join(f'{toml_key(k)} = {toml_value(v)}' for k, v in value.items()) + ' }'
    raise ValueError(f'Unsupported TOML value: {type(value).__name__}')


def dump_toml(data):
    lines = []
    def table(node, path=()):
        if path:
            lines.extend(['', '[' + '.'.join(toml_key(k) for k in path) + ']'])
        for key, value in node.items():
            if not isinstance(value, dict):
                lines.append(f'{toml_key(key)} = {toml_value(value)}')
        for key, value in node.items():
            if isinstance(value, dict):
                table(value, (*path, key))
    table(data)
    text = '\n'.join(lines).lstrip() + '\n'
    # This also rejects accidental serializer regressions before any write.
    if not equivalent(tomllib.loads(text), data):
        raise ValueError('TOML serialization changed configuration values')
    return text


def equivalent(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
    if isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b):
        return True
    return type(a) is type(b) and a == b


def reconcile_toml(text, overlay, remove=(), header=''):
    original = tomllib.loads(text)
    data = deepcopy(original)
    for key in remove:
        data.pop(key, None)
    data = merge(data, overlay)
    if equivalent(data, original):
        return text
    return header + dump_toml(data)


def backup(path, root):
    path, root = Path(path), Path(root)
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    if root.is_symlink():
        raise ValueError(f'Refusing symlinked backup directory: {root}')
    root.chmod(0o700)
    directory = Path(tempfile.mkdtemp(prefix=path.name + '.', dir=root))
    shutil.copy2(path, directory / path.name, follow_symlinks=False)
    if not (directory / path.name).is_symlink():
        (directory / path.name).chmod(0o600)
    return directory / path.name


def write_file(path, content, backup_dir, dry_run=False, mode=0o600):
    path = Path(path)
    check_target(path)
    if path.exists() and path.read_bytes() == content:
        print(f'current: {path}')
        return False
    if dry_run:
        print(f'would update: {path} (backups: {backup_dir})')
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        print(f'backup: {backup(path, backup_dir)}')
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f'updated: {path}')
    return True
