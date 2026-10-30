"""The build cache: one directory per checkout under $XDG_CACHE_HOME/keys.

A build writes keymap.json (layers, traces, findings), entries.json (the entry
index), index.tsv (its rows for fzf) and apps.tsv (pane command -> app), then the
stamp, which holds the commit. The cache is fresh while the commit matches and no
input (lib/keymap/inputs, and the tmux binary) is newer than the stamp; bin/keys
makes the same test in bash, so a lookup starts without Python.
"""
import datetime
import json
import os
import shutil
import subprocess
import tempfile

from . import route, views

HERE = os.path.dirname(os.path.abspath(__file__))


def directory(repo):
    base = os.environ.get('XDG_CACHE_HOME') or os.path.expanduser('~/.cache')
    return os.path.join(base, 'keys', os.path.realpath(repo).replace('/', '%'))


def inputs(repo, tmux_bin=None):
    """The files a build reads: lib/keymap/inputs (one path per line) and the tmux binary."""
    out = []
    with open(os.path.join(HERE, 'inputs')) as f:
        for line in f:
            line = line.split('#')[0].strip()
            if line and os.path.exists(os.path.join(repo, line)):
                out.append(os.path.join(repo, line))
    tmux = tmux_bin or shutil.which('tmux')
    if tmux:
        out.append(os.path.realpath(tmux))
    return out


def git(repo, *args):
    r = subprocess.run(['git', '-C', repo, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else '?'


def newer(paths, stamp_time):
    for p in paths:
        if os.path.isfile(p):
            if os.path.getmtime(p) > stamp_time:
                return p
            continue
        for root, dirs, files in os.walk(p):
            dirs[:] = [d for d in dirs if d != '__pycache__']
            for f in files:
                fp = os.path.join(root, f)
                try:
                    if os.path.getmtime(fp) > stamp_time:
                        return fp
                except OSError:
                    continue
    return None


def fresh(repo, tmux_bin=None):
    stamp = os.path.join(directory(repo), 'stamp')
    try:
        with open(stamp) as f:
            commit = f.read().strip()
        when = os.path.getmtime(stamp)
    except OSError:
        return False
    return commit == git(repo, 'rev-parse', 'HEAD') and not newer(inputs(repo, tmux_bin), when)


def write(path, text):
    """Write atomically, so a lookup reading the cache never sees half a file."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.' + os.path.basename(path))
    with os.fdopen(fd, 'w') as f:
        f.write(text)
    os.replace(tmp, path)


def index_doc(data, found, groups, meta):
    """entries.json: everything the shell views and the preview need, without the traces."""
    from . import entries
    labels = {a['id']: a['label'] for a in data['apps']}
    presses = {}
    for e in found:
        if e.kind in ('chord', 'intent'):
            first = 'ctrl+a' if e.layer == 'tmux-prefix' else e.key.split(' ')[0]
            p = data['presses'].get(first)
            if p:
                presses[first] = views.press_text(p)
    return dict(meta=meta, labels=labels, presses=presses, groups=groups, versions=data['versions'],
                notes=data['notes'], entries=entries.to_json(found))


def build(repo, tmux_bin=None, decorate=None):
    """Build afresh and write the cache. DECORATE(index) marks changed entries (keys diff).
    Returns (data, index, problems)."""
    from . import analysis, entries
    out = directory(repo)
    os.makedirs(out, exist_ok=True)
    started = datetime.datetime.now().timestamp()
    data, model = analysis.build(repo, tmux_bin)
    data['meta'] = dict(branch=git(repo, 'rev-parse', '--abbrev-ref', 'HEAD'), commit=git(repo, 'rev-parse', '--short', 'HEAD'),
                        date=datetime.date.today().isoformat())
    found, problems = entries.build(repo, data, model)
    groups = entries.load_notes(repo).get('group', {})
    index = index_doc(data, found, groups, dict(data['meta'], full=git(repo, 'rev-parse', 'HEAD'), repo=repo))
    if decorate:
        decorate(index)
    save(repo, data, index)
    stamp = os.path.join(out, 'stamp')
    write(stamp, index['meta']['full'] + '\n')
    os.utime(stamp, (started, started))  # an input saved during the build leaves it stale
    return data, index, problems


def save(repo, data, index):
    out = directory(repo)
    os.makedirs(out, exist_ok=True)
    if data is not None:
        write(os.path.join(out, 'keymap.json'), json.dumps(data, separators=(',', ':')))
    write(os.path.join(out, 'entries.json'), json.dumps(index, separators=(',', ':')))
    write_index(repo, index)


def write_index(repo, index):
    out = directory(repo)
    lines = views.index_lines(index['entries'], index['groups'], index['labels'])
    write(os.path.join(out, 'index.tsv'), '\n'.join(lines) + '\n')
    cmds = [f"{v['cmd']}\t{a}" for a, v in route.APPS.items() if a != 'copy'] + ['zsh\tshell', 'sh\tshell']
    write(os.path.join(out, 'apps.tsv'), '\n'.join(cmds) + '\n')


def load(repo, name):
    try:
        with open(os.path.join(directory(repo), name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def ensure(repo, tmux_bin=None, quiet=False):
    """(data, index) from the cache, built first when missing or stale."""
    data, index = load(repo, 'keymap.json'), load(repo, 'entries.json')
    if data is None or index is None or not fresh(repo, tmux_bin):
        from . import track
        data, index, _ = build(repo, tmux_bin, decorate=lambda ix: track.decorate(repo, ix))
    return data, index
