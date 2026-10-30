"""What changed: snapshots of the entry index, the seen baseline, and keys diff.

A snapshot is what can change about each entry (its key, summary, status,
origin, and a digest of what it does in each program) plus the broken keys. A
build of a clean checkout keeps one per commit under $XDG_STATE_HOME/keys/
snapshots (the last 30). keys seen stores the current one as the baseline
(seen.json); every build marks the entries that differ from it, which is
what the lookup's ● marker, its Ctrl+R list and the page's What changed show.
keys diff REV compares with REV's snapshot, or builds one from `git archive REV`
with the current lib/keymap when there is none.
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import tempfile

KEEP = 30
FIELDS = ('kind', 'key', 'label', 'layer', 'summary', 'status', 'origin')


def state_dir():
    base = os.environ.get('XDG_STATE_HOME') or os.path.expanduser('~/.local/state')
    return os.path.join(base, 'keys')


def digest(value):
    return hashlib.sha1(json.dumps(value, sort_keys=True).encode()).hexdigest()[:10]


def snapshot(index, findings=None):
    """{entries: {id: {field: value, apps: digest}}, broken: [...], commit, date}."""
    rows = {}
    for e in index['entries']:
        row = {k: e.get(k, '') for k in FIELDS}
        if e.get('apps'):
            row['apps'] = digest(e['apps'])
        rows[e['id']] = row
    broken = sorted(findings if findings is not None else index.get('broken', []))
    meta = index.get('meta', {})
    return dict(commit=meta.get('full') or meta.get('commit', ''), date=meta.get('date', ''), entries=rows, broken=broken,
                hash=digest([rows, broken]))


def compare(old, new):
    """The difference between two snapshots: added, changed (with the fields), removed, and
    broken keys new or fixed."""
    a, b = old['entries'], new['entries']
    added = sorted(set(b) - set(a))
    removed = sorted(set(a) - set(b))
    changed = []
    for i in sorted(set(a) & set(b)):
        fields = [k for k in FIELDS + ('apps',) if a[i].get(k, '') != b[i].get(k, '')]
        if fields:
            changed.append((i, fields))
    return dict(added=added, removed=removed, changed=changed,
                new=sorted(set(new['broken']) - set(old['broken'])), fixed=sorted(set(old['broken']) - set(new['broken'])))


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(path, value):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(value, f, separators=(',', ':'))
    os.replace(tmp, path)


def clean(repo):
    """Whether the checkout's inputs match its commit, so a snapshot can carry its name."""
    r = subprocess.run(['git', '-C', repo, 'status', '--porcelain', '--untracked-files=no'], capture_output=True, text=True)
    return r.returncode == 0 and not r.stdout.strip()


def keep_snapshot(repo, snap):
    folder = os.path.join(state_dir(), 'snapshots')
    if not snap['commit'] or snap['commit'] == '?' or not clean(repo):
        return
    save(os.path.join(folder, snap['commit'] + '.json'), snap)
    files = sorted((os.path.join(folder, f) for f in os.listdir(folder) if f.endswith('.json')), key=os.path.getmtime)
    for old in files[:-KEEP]:
        os.remove(old)


def changes_doc(base, snap, index, label):
    """What the page's What changed section and the lookup show."""
    d = compare(base, snap)
    by = {e['id']: e for e in index['entries']}

    def row(i, fields=None, gone=None):
        e = by.get(i) or gone or {}
        out = dict(id=i, key=e.get('key', ''), label=e.get('label', i), layer=e.get('layer', ''), summary=e.get('summary', ''))
        if fields:
            out['fields'] = fields
        return out
    return dict(since=label, sinceDate=base.get('date', ''), hash=snap['hash'],
                added=[row(i) for i in d['added']], changed=[row(i, f) for i, f in d['changed']],
                removed=[row(i, gone=base['entries'][i]) for i in d['removed']],
                findings=dict(new=d['new'], fixed=d['fixed']))


def decorate(repo, index, findings=None):
    """Mark entries changed since the seen baseline, keep this commit's snapshot, and put
    the differences in index['changes']. The first build, with no baseline yet, marks none."""
    snap = snapshot(index, findings)
    index['broken'] = snap['broken']
    keep_snapshot(repo, snap)
    seen = load(os.path.join(state_dir(), 'seen.json'))
    if not seen:  # the first build is the baseline, so later changes show
        snap['seen'] = datetime.datetime.now().isoformat(timespec='seconds')
        save(os.path.join(state_dir(), 'seen.json'), snap)
        index['changes'] = {}
        return index
    doc = changes_doc(seen, snap, index, (seen.get('commit') or '')[:9] or 'the baseline')
    marks = {r['id']: 'added' for r in doc['added']}
    marks.update({r['id']: 'changed' for r in doc['changed']})
    for e in index['entries']:
        e['changed'] = marks.get(e['id'], '')
    index['changes'] = doc
    return index


def mark_seen(index):
    """keys seen: the current index becomes the baseline."""
    snap = snapshot(index)
    snap['seen'] = datetime.datetime.now().isoformat(timespec='seconds')
    save(os.path.join(state_dir(), 'seen.json'), snap)
    for e in index['entries']:
        e['changed'] = ''
    index['changes'] = {}
    return snap


def resolve(repo, rev):
    """A commit for REV; '7d' is the commit seven days back."""
    m = re.fullmatch(r'(\d+)([dwh])', rev or '')
    if m:
        unit = {'d': 'days', 'w': 'weeks', 'h': 'hours'}[m.group(2)]
        r = subprocess.run(['git', '-C', repo, 'rev-list', '-1', f'--before={m.group(1)} {unit} ago', 'HEAD'],
                           capture_output=True, text=True)
    else:
        r = subprocess.run(['git', '-C', repo, 'rev-parse', '--verify', '--quiet', (rev or 'HEAD') + '^{commit}'],
                           capture_output=True, text=True)
    return r.stdout.strip() or None


def snapshot_of(repo, commit, tmux_bin=None):
    """REV's snapshot: kept from an earlier build, or built from `git archive` with the current
    lib/keymap (its readers all take the checkout as a parameter)."""
    kept = load(os.path.join(state_dir(), 'snapshots', commit + '.json'))
    if kept:
        return kept
    from . import analysis, cache, entries
    with tempfile.TemporaryDirectory() as tmp:
        tree = os.path.join(tmp, 'tree')
        os.makedirs(tree)
        r = subprocess.run(['bash', '-c', 'set -o pipefail; git -C "$1" archive --format=tar "$2" | tar -x -C "$3"', '_',
                            repo, commit, tree], capture_output=True, text=True)
        if r.returncode:
            raise SystemExit(f'keys diff: git archive {commit[:9]} failed: {r.stderr.strip()}')
        data, model = analysis.build(tree, tmux_bin)
        found, _ = entries.build(tree, data, model)
        date = subprocess.run(['git', '-C', repo, 'show', '-s', '--format=%cs', commit], capture_output=True, text=True).stdout.strip()
        index = cache.index_doc(data, found, {}, dict(full=commit, commit=commit[:9], date=date))
        bugs = sorted({analysis.finding_key(f) for f in data['findings'] if f['sev'] == 'bug'})
        snap = snapshot(index, bugs)
    save(os.path.join(state_dir(), 'snapshots', commit + '.json'), snap)
    return snap


def describe(doc, paint, limit=40):
    """keys diff as text."""
    out = []
    head = f"since {doc['since']}" + (f" ({doc['sinceDate']})" if doc.get('sinceDate') else '')
    total = sum(len(doc[k]) for k in ('added', 'changed', 'removed')) + len(doc['findings']['new']) + len(doc['findings']['fixed'])
    out.append(paint.bold(f'{total} changes {head}') if total else f'Nothing changed {head}.')

    def line(r, mark):
        layer = r['layer'] if r['layer'] not in ('shell', 'bin', 'git') else ''
        extra = paint.dim(f" ({', '.join(r['fields'])})") if r.get('fields') else ''
        return f"  {mark} {paint.key(r['label'][:22].ljust(22))} {paint.layer(layer.ljust(10))} {r['summary'][:70]}{extra}"
    for k, mark, title in (('added', '+', 'Added'), ('changed', '~', 'Changed'), ('removed', '-', 'Removed')):
        if doc[k]:
            out.append(paint.layer(title))
            out += [line(r, mark) for r in doc[k][:limit]]
            if len(doc[k]) > limit:
                out.append(paint.dim(f'  … and {len(doc[k]) - limit} more (keys ls --changed)'))
    for k, title in (('new', 'Newly broken'), ('fixed', 'Fixed')):
        if doc['findings'][k]:
            out.append(paint.layer(title))
            out += ['  ' + f for f in doc['findings'][k]]
    return '\n'.join(out)


# --- keys defaults: what an agent upgrade moved ----------------------------------------------------------
def binding_set(app, d):
    """{(context, action, key)} from a saved defaults file."""
    out = set()
    if not d:
        return out
    for ctx, b in d['bindings'].items():
        if app == 'claude':
            out |= {(ctx, action, key) for key, action in b.items()}
        elif isinstance(b, dict):  # codex: context -> action -> keys
            out |= {(ctx, action, key) for action, keys in b.items() for key in keys}
        else:  # opencode, pi: action -> keys
            out |= {('', ctx, key) for key in ([b] if isinstance(b, str) else b)}
    return out


def defaults_diff(app, old, new):
    a, b = binding_set(app, old), binding_set(app, new)
    keys_of = lambda s: {(c, x): sorted(k for cc, xx, k in s if (cc, xx) == (c, x)) for c, x, _ in s}  # noqa: E731
    ka, kb = keys_of(a), keys_of(b)
    rebound = sorted((c, x, ka[(c, x)], kb[(c, x)]) for (c, x) in set(ka) & set(kb) if ka[(c, x)] != kb[(c, x)])
    moved = {(c, x) for c, x, _, _ in rebound}
    added = sorted((c, x, k) for c, x, k in b - a if (c, x) not in moved)
    removed = sorted((c, x, k) for c, x, k in a - b if (c, x) not in moved)
    return dict(version=[(old or {}).get('version'), (new or {}).get('version')], added=added, removed=removed,
                rebound=rebound)


def describe_defaults(app, d, paint):
    v = d['version']
    head = f"{app}: {v[0]} -> {v[1]}" if v[0] != v[1] else f'{app}: {v[1]}'
    if not (d['added'] or d['removed'] or d['rebound']):
        return f'{head}, no binding changed'
    out = [paint.bold(head)]
    ctx = lambda c: f' ({c})' if c else ''  # noqa: E731
    out += [f'  + {x}{ctx(c)}: {k}' for c, x, k in d['added']]
    out += [f'  - {x}{ctx(c)}: {k}' for c, x, k in d['removed']]
    out += [f"  ~ {x}{ctx(c)}: {', '.join(o) or 'none'} -> {', '.join(n) or 'none'}" for c, x, o, n in d['rebound']]
    return '\n'.join(out)
