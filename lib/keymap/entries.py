"""The entry index: every binding, intent, alias, function, git alias and command as one flat record.

entries.build turns a build (analysis.build's data and model) and the readers in
names.py into Entry records, then lays configs/keymap/notes.toml on top: notes
override or add a summary, groups collapse rows, tips add what no config states,
and hide drops entries. check() reports notes that no longer match anything.
"""
import fnmatch
import json
import os
import re
import tomllib
from dataclasses import asdict, dataclass, field

from . import chord, names, route

NOTES = 'configs/keymap/notes.toml'
KIND_ORDER = ['intent', 'chord', 'tip', 'alias', 'function', 'git-alias', 'command']
LAYER_LABEL = {'tmux-prefix': 'tmux pfx', 'tmux-copy': 'copy', 'shell': 'bash', 'bin': 'command'}
# Where each layer acts: an app id for the pane programs, all of them for the outer layers.
OUTER = ('windows', 'wezterm', 'tmux', 'tmux-prefix', 'tmux-mouse')
LAYER_APP = {'tmux-copy': 'copy', 'zsh': 'shell', 'git': 'shell', 'bin': 'shell'}
# What a reader's own note is called, for `via`.
NOTE_VIA = {'tmux': 'tmux-N', 'tmux-prefix': 'tmux-N', 'tmux-copy': 'tmux-N', 'tmux-mouse': 'tmux-N', 'nvim': 'desc', 'opencode': 'desc',
            'pi': 'desc'}


@dataclass
class Entry:
    id: str            # stable key: tmux:alt+z, claude:alt+m@Chat, alias:gs, cmd:viz
    kind: str          # chord | intent | alias | function | git-alias | command | tip
    key: str           # canonical chord 'alt+z' / 'ctrl+a z', or the name 'gs'
    label: str         # 'Alt+Z', 'Ctrl+A Z', 'gs'
    layer: str         # windows|wezterm|tmux|tmux-prefix|tmux-copy|shell|zsh|fzf|nvim|claude|codex|opencode|pi|git|bin
    context: str = ''  # 'mode n', 'Chat', 'composer'
    summary: str = ''  # one line, the best description there is
    via: str = ''      # where summary came from: note|tmux-N|comment|desc|docstring|friendly|action
    expands: str = ''  # alias body, tmux command, action id
    origin: str = 'stock'   # stock | ours
    apps: dict = field(default_factory=dict)   # app -> what the key does there (outer layers: every app)
    scope: list = field(default_factory=list)  # apps it acts in, for `keys --app` and the popup
    status: str = ''   # '' | bug | adapted | cost | unpressable
    cause: str = ''    # why, for a status: 'tmux takes it: focus pane left'
    intent: str = ''   # the intent id it serves
    press: str = ''    # easy | one hand | tight | stretch | unpressable
    tags: list = field(default_factory=list)
    group: str = ''    # group id, for rows collapsed in the default view
    source: str = ''   # configs/tmux.conf:303
    changed: str = ''  # '' | added | changed (against the baseline, keys diff)


def human(action):
    """'chat:modelPicker' -> 'model picker'; a command line stays as it is."""
    if not re.fullmatch(r'[\w.:-]+', action or ''):
        return action or ''
    last = re.split(r'[:.]', action)[-1]
    return re.sub(r'([a-z])([A-Z])', r'\1 \2', last).replace('_', ' ').replace('-', ' ').lower().strip()


def label_of(layer, key):
    """People's names for a chord; Neovim's sequences read as typed (,gs, ysiw, <Ctrl+G>s)."""
    if layer != 'nvim':
        return chord.label(key)
    out = ''
    for stroke in key.split(' '):
        out += stroke if len(stroke) == 1 else ('Space' if stroke == 'space' and ' ' not in key else '<' + chord.label(stroke) + '>')
    return out[1:-1] if out.count('<') == 1 and out.startswith('<') and out.endswith('>') else out


def hop_text(h):
    """A hop in words, chords as people write them, without the rule's bookkeeping."""
    text = re.sub(r' \((?:rule|fallback) for [^)]*\)', '', h[2])
    text = re.sub(r'^(sends|arrives as) (.+)$', lambda m: m.group(1) + ' ' + chord.label(m.group(2)), text)
    return f'{h[0]}: {text}'


def outcome(app, r, labels):
    """One app's result for a trace, in words: 'tmux: sends Esc Esc ⇒ rewind'. Hops that
    only pass the key on are left out, so a key that goes straight through reads '⇒ action'."""
    path = ' → '.join(hop_text(h) for h in r['hops'] if h[1] not in ('pass', 'cond'))
    own = [e for e in r['effects'] if e[0] == app]
    if own:
        result = human(own[0][2])
    elif r['delivered'] is None:
        taken = next((h for h in r['hops'] if h[1] == 'consume'), None)
        return hop_text(taken) if taken else 'taken before it arrives'
    else:
        result = 'nothing'
    return (path + ' ⇒ ' if path else '⇒ ') + result


def acts(r):
    """Whether an outer layer does something with the key in this pane: takes it (to some
    effect) or rewrites it."""
    if r['delivered'] is None:
        return any(e[1] != 'nothing' for e in r['effects'])
    return any(h[0] in ('windows', 'wezterm', 'tmux') and h[1] == 'rewrite' for h in r['hops'])


def chord_id(layer, ch, ctx):
    ctx = '' if layer in OUTER[:-1] + ('tmux-copy', 'fzf', 'opencode', 'shell', 'zsh') else ctx
    return f'{layer}:{ch}' + (f'@{ctx}' if ctx else '')


def from_bindings(bindings, data):
    """Chord entries, one per layer, chord and context; a second action on the same
    one joins the first ('interrupt; close dialog')."""
    labels = {a['id']: a['label'] for a in data['apps']}
    traces = data['traces']
    found = {}
    for b in bindings:
        if b.layer == 'windows' and 'super' in b.chord:
            continue
        ctx = b.context.replace('mode ', '') if b.layer == 'nvim' else b.context
        eid = chord_id(b.layer, b.chord, ctx)
        action = b.action
        if b.layer == 'tmux-copy':
            cmds = re.findall(r'send(?:-keys)? -X (\S+)', b.action)
            action = cmds[-1] if cmds else b.action
        origin = 'ours' if b.origin == 'ours' or b.source.startswith(('configs/', 'entry/', 'shell/')) else 'stock'
        if b.note:
            summary, via = b.note, NOTE_VIA.get(b.layer, 'comment')
        elif b.layer in ('tmux', 'tmux-prefix'):
            fid, label = route.friendly(b.action)
            matched = fid.split('-')[0] != (b.action.split() or [''])[0].split('-')[0] or label != b.action[:48]
            summary, via = (label, 'friendly') if matched else (b.action, 'action')
        else:
            summary, via = human(action), 'action'
        e = found.get(eid)
        if e:
            if summary and summary not in e.summary.split('; '):
                e.summary += '; ' + summary
            e.expands += '; ' + action if action not in e.expands.split('; ') else ''
            e.origin = 'ours' if origin == 'ours' else e.origin
            continue
        key = b.chord if b.layer != 'tmux-prefix' else 'ctrl+a ' + b.chord
        e = Entry(id=eid, kind='chord', key=key, label=label_of(b.layer, key), layer=b.layer, context=ctx, summary=summary,
                  via=via, expands=action if b.layer not in ('windows',) else '', origin=origin, source=b.source,
                  tags=[ctx] if b.layer in ('claude', 'codex', 'pi') and ctx else [])
        first = b.chord.split(' ')[0]
        t = traces.get(first)
        if b.layer in ('windows', 'wezterm', 'tmux') and t:
            e.apps = {a: outcome(a, r, labels) for a, r in t.items()}
            e.scope = [a for a, r in t.items() if acts(r)] or list(t)
        elif b.layer == 'tmux-mouse' and ctx == 'copy':
            e.scope = ['copy']
        elif b.layer in OUTER:
            e.scope = list(route.APPS)
        else:
            app = LAYER_APP.get(b.layer, b.layer)
            e.scope = [app]
            if t and app in t:
                e.apps = {app: outcome(app, t[app], labels)}
        p = data['presses'].get(first) if ' ' not in key or b.layer == 'tmux-prefix' else None
        e.press = (p or {}).get('rating', '')
        found[eid] = e
    return found


def same_in_zsh(found):
    """A zsh binding that does what bash's does on the same key is one entry, tagged zsh."""
    def widget(e):
        return re.sub(r' widget$', '', human(e.expands.strip('_ ')).replace('_', ' '))
    for eid in [i for i, e in found.items() if e.layer == 'zsh']:
        z, b = found[eid], found.get('shell:' + found[eid].key)
        if b and b.origin == 'ours' and widget(b) == widget(z):
            b.tags = list(dict.fromkeys(b.tags + ['bash', 'zsh']))
            b.source += ', ' + z.source
            del found[eid]


def judge(found, data):
    """Findings become a status; intents mark the keys that serve them."""
    by_action = {}
    for e in found.values():
        for action in e.expands.split('; '):
            by_action.setdefault((LAYER_APP.get(e.layer, e.layer), e.key, action), e)
    for f in data['findings']:
        if f.get('kind') == 'unpressable':
            e = found.get(f"{f['layer']}:{f['chord']}")
            if e:
                e.status, e.cause = 'unpressable', 'no key on the keyboard sends it'
            continue
        e = by_action.get((f['app'], f['chord'], f['action']))
        if e and (not e.status or f['sev'] == 'bug'):
            e.status, e.cause = f['sev'], f['cause']


def intent_entries(spec, data, found):
    out = []
    rows = {it['label']: it for it in data['intents']}
    for it in spec:
        iid = it.get('id') or re.sub(r'[^a-z0-9]+', '-', it['label'].lower()).strip('-')
        row = rows.get(it['label'], {})
        canon = it.get('canon') or ''
        apps = {a: (('✓ ' if v['status'] == 'ok' else '') + ', '.join(chord.label(c) for c, _ in v['chords'][:3])
                    or v['status']) for a, v in row.get('apps', {}).items()}
        out.append(Entry(id='intent:' + iid, kind='intent', key=canon or iid, label=chord.label(canon) if canon else '—',
                         layer='intent', context=it['group'], summary=it['label'] + (': ' + it['note'] if it.get('note') else ''),
                         via='note', origin='ours', apps=apps, scope=sorted(it['apps']), intent=iid,
                         press=((row.get('press') or {}).get('rating') or ''), tags=[it['group'].lower()],
                         source='configs/keymap/intents.json'))
        for e in found.values():
            if e.intent:
                continue
            app = LAYER_APP.get(e.layer, e.layer)
            actions = it['apps'].get(app, [])
            if e.kind == 'chord' and (set(e.expands.split('; ')) & set(actions) or
                                      (e.layer in ('tmux', 'wezterm') and canon and e.key == canon)):
                e.intent = iid
    return out


def load_notes(repo):
    path = os.path.join(repo, NOTES)
    if not os.path.exists(path):
        return {}
    with open(path, 'rb') as f:
        return tomllib.load(f)


def apply_notes(entries, notes, repo, plugins=True):
    """Lay the curated layer over the derived entries. Returns the problems for keys check.
    Without Neovim's plugins (CI), the maps init.vim sets for them are missing, so notes
    on Neovim keys that match nothing are not counted against the notes."""
    problems = []
    by_id = {e.id: e for e in entries}
    for nid, n in notes.get('note', {}).items():
        for target in [nid] + list(n.get('also', [])):
            e = by_id.get(target)
            if not e:
                if plugins or not target.startswith('nvim:'):
                    problems.append(f'{NOTES}: note "{target}" matches no entry')
                continue
            if n.get('summary'):
                e.summary, e.via = n['summary'], 'note'
            if n.get('expands'):
                e.expands = n['expands']
            e.tags = list(dict.fromkeys(e.tags + list(n.get('tags', []))))
    for gid, g in notes.get('group', {}).items():
        members = [e for e in entries if fnmatch.fnmatchcase(e.id, g['match'])]
        if not members:
            problems.append(f'{NOTES}: group "{gid}" ({g["match"]}) matches no entry')
        for e in members:
            e.group = gid
    for tid, t in notes.get('tip', {}).items():
        anchor = t.get('anchor')
        if anchor:
            try:
                with open(os.path.join(repo, anchor[0])) as f:
                    if anchor[1] not in f.read():
                        problems.append(f'{NOTES}: tip "{tid}": "{anchor[1]}" is no longer in {anchor[0]}')
            except OSError:
                problems.append(f'{NOTES}: tip "{tid}": {anchor[0]} is gone')
        layer = t.get('layer', 'shell')
        app = LAYER_APP.get(layer, layer)
        scope = t.get('apps') or ([app] if app in route.APPS else list(route.APPS) if layer in OUTER else ['shell'])
        entries.append(Entry(id='tip:' + tid, kind=t.get('kind', 'tip'), key=t.get('key', t['label']), label=t['label'],
                             layer=layer, summary=t['summary'], via='note', expands=t.get('expands', ''), origin='ours',
                             scope=scope, tags=list(t.get('tags', [])), intent=t.get('intent', ''),
                             source=f'{anchor[0]}' if anchor else NOTES))
    hide = set(notes.get('hide', {}).get('ids', []))
    for h in sorted(hide - set(by_id)):
        problems.append(f'{NOTES}: hide "{h}" matches no entry')
    entries[:] = [e for e in entries if e.id not in hide]
    return problems


def named(repo):
    out = []
    for d in names.shell(repo) + names.git_aliases(repo) + names.commands(repo):
        out.append(Entry(scope=['shell'], **d))
    return out


def build(repo, data, model):
    """(entries, problems) for a build of REPO."""
    found = from_bindings(model.bindings, data)
    same_in_zsh(found)
    judge(found, data)
    with open(os.path.join(repo, 'configs/keymap/intents.json')) as f:
        spec = json.load(f)['intents']
    entries = intent_entries(spec, data, found) + list(found.values()) + named(repo)
    plugins = any(b.layer == 'nvim' and b.source.startswith('plugin') for b in model.bindings)
    problems = apply_notes(entries, load_notes(repo), repo, plugins)
    ids = [e.id for e in entries]
    problems += [f'duplicate entry id: {i}' for i in sorted({i for i in ids if ids.count(i) > 1})]
    entries.sort(key=lambda e: (KIND_ORDER.index(e.kind) if e.kind in KIND_ORDER else 9, e.layer, e.key))
    return entries, problems


def to_json(entries):
    return [asdict(e) for e in entries]


def from_json(rows):
    return [Entry(**r) for r in rows]


def undescribed(entries):
    """Our own entries with no description but their action: the description ratchet."""
    return sorted(e.id for e in entries if e.origin == 'ours' and e.via in ('action', 'friendly')
                  and e.kind in ('chord', 'alias', 'function', 'git-alias', 'command'))
