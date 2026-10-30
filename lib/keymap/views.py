"""Text views of the entry index: list rows, the fzf index, the preview card, and the compact trace."""
import os
import re
import sys

from . import chord, route

APP_ORDER = list(route.APPS)
# 256-color numbers near the page's layer hues (page.html :root), for the board and markers.
HUE = {'windows': 33, 'wezterm': 99, 'tmux': 36, 'app': 250, 'free': 240, 'bug': 167, 'warn': 172, 'ok': 71}


class Paint:
    """ANSI styling, or none when NO_COLOR is set or the output isn't a terminal."""

    def __init__(self, on):
        self.on = on

    def __call__(self, code, text):
        return f'\033[{code}m{text}\033[0m' if self.on and text else text

    def c256(self, n, text):
        return self(f'38;5;{n}', text)

    bold = lambda self, t: self('1', t)  # noqa: E731
    dim = lambda self, t: self('2', t)  # noqa: E731
    key = lambda self, t: self('33', t)  # noqa: E731
    layer = lambda self, t: self('36', t)  # noqa: E731


def paint_for(stream=None, force=None):
    if force is not None:
        return Paint(force)
    stream = stream or sys.stdout
    return Paint(stream.isatty() and not os.environ.get('NO_COLOR'))


def layer_label(e):
    return {'tmux-prefix': 'tmux pfx', 'tmux-copy': 'copy', 'bin': 'command', 'git': 'git',
            'intent': 'intent'}.get(e['layer'], e['layer']) if e['kind'] != 'alias' and e['kind'] != 'function' \
        else e['kind']


def marker(e):
    if e.get('changed'):
        return '●'
    if e['status'] in ('bug', 'unpressable'):
        return '✗'
    if e['status'] == 'adapted':
        return '~'
    if e['origin'] == 'stock':
        return '·'
    return ' '


def summary_of(e):
    return e['summary'] or e['expands'] or ''


def internal(e):
    return 'internal' in e['tags']


def filtered(entries, args, groups=None):
    """Entries that pass the shared filters (keys, ls, card)."""
    kinds = set(args.kind.split(',')) if getattr(args, 'kind', None) else None
    layers = set(args.layer.split(',')) if getattr(args, 'layer', None) else None
    tags = set(args.tag.split(',')) if getattr(args, 'tag', None) else None
    mods = set(args.mods.split('+')) if getattr(args, 'mods', None) else None
    out = []
    for e in entries:
        if kinds and e['kind'] not in kinds:
            continue
        if layers and e['layer'] not in layers and layer_label(e) not in layers:
            continue
        if tags and not tags & set(t.lower() for t in e['tags']):
            continue
        if getattr(args, 'app', None) and args.app not in e['scope']:
            continue
        if mods is not None and (e['kind'] != 'chord' or chord.split(e['key'].split(' ')[0])[0] != mods):
            continue
        if getattr(args, 'changed', False) and not e.get('changed'):
            continue
        if getattr(args, 'broken', False) and e['status'] not in ('bug', 'unpressable'):
            continue
        everything = getattr(args, 'all', False)
        if e['origin'] == 'stock' and not (getattr(args, 'stock', False) or everything):
            continue
        if internal(e) and not everything and not (kinds and 'command' in kinds and getattr(args, 'all', False)):
            continue
        out.append(e)
    return out


def collapse(entries, groups):
    """Members of a notes.toml group become one row, where the first member stood."""
    out, done = [], set()
    for e in entries:
        g = e.get('group')
        if not g or g not in groups:
            out.append(e)
            continue
        if g in done:
            continue
        done.add(g)
        members = [m for m in entries if m.get('group') == g]
        spec = groups[g]
        out.append(dict(members[0], id='group:' + g, label=spec.get('label', members[0]['label']),
                        summary=spec.get('summary', members[0]['summary']), via='note',
                        members=[m['id'] for m in members], key=spec.get('label', members[0]['key'])))
    return out


def row(e, paint, width=None):
    """One aligned line: marker, label (18), layer (10), summary, ⟨intent⟩."""
    mark = marker(e)
    mark = {'●': paint('33', '●'), '✗': paint.c256(HUE['bug'], '✗'), '~': paint.c256(HUE['tmux'], '~'),
            '·': paint.dim('·')}.get(mark, ' ')
    label = e['label'] if len(e['label']) <= 18 else e['label'][:17] + '…'
    text = summary_of(e)
    intent = f"  ⟨{e['intent']}⟩" if e.get('intent') and e['kind'] != 'intent' else ''
    if width:
        room = max(10, width - 33 - len(intent))
        text = text if len(text) <= room else text[:room - 1] + '…'
    return f"{mark} {paint.key(label.ljust(18))} {paint.layer(layer_label(e).ljust(10))} {text}{paint.dim(intent)}"


def copy_text(e):
    """What Enter copies: the chord as people write it, or the name to type."""
    if e['kind'] in ('alias', 'function', 'command', 'git-alias'):
        return e['key']
    return e['label']


def flags(e):
    out = 's' if e['origin'] == 'stock' else 'o'
    out += 'i' if internal(e) else ''
    out += 'g' if e.get('group') and not e['id'].startswith('group:') else ''
    out += 'c' if e.get('changed') else ''
    out += 'h' if e['kind'] in ('alias', 'function', 'git-alias', 'command') else ''
    out += 'x' if e['status'] in ('bug', 'unpressable') else ''
    return out


# Hidden search text sits after this much padding: past the right edge of any
# popup, so fzf matches app names, tags and expansions without showing them.
PAD = ' ' * 300


def index_lines(entries, groups, labels):
    """The fzf index: id, kind, flags, scope, key, copy text, display (+ hidden search terms).
    Group members stay in it (flag g) so --all can show them; the group row comes first."""
    paint = Paint(True)
    rows = collapse(entries, groups)
    member_rows = [e for e in entries if e.get('group')]
    out = []
    for e in rows + member_rows:
        search = ' '.join([e['id'], ' '.join(labels.get(a, a) for a in e['scope']), ' '.join(e['tags']),
                           e['expands'][:120], e['key']])
        display = row(e, paint) + PAD + paint.dim(search.replace('\t', ' '))
        cells = [e['id'], e['kind'], flags(e) + ('m' if e in member_rows and not e['id'].startswith('group:') else ''),
                 ','.join(e['scope']), e['key'].lower(), copy_text(e), display]
        out.append('\t'.join(c.replace('\t', ' ').replace('\n', ' ') for c in cells))
    return out


TSV_COLUMNS = ['id', 'kind', 'label', 'layer', 'summary', 'intent', 'status', 'origin', 'scope', 'tags', 'source']


def tsv(entries):
    out = []
    for e in entries:
        vals = [e['id'], e['kind'], e['label'], e['layer'], summary_of(e), e.get('intent', ''), e['status'], e['origin'],
                ','.join(e['scope']), ','.join(e['tags']), e['source']]
        out.append('\t'.join(str(v).replace('\t', ' ').replace('\n', ' ') for v in vals))
    return out


# --- The compact trace -------------------------------------------------------------------------
def merged_outcomes(apps, labels):
    """[(app labels, line)]: apps with the same outcome share a line, and so do apps whose
    route is the same but whose own actions differ ('⇒ rewind / edit previous'); apps where
    the key does nothing collapse into one line at the end."""
    groups, nothing = {}, []
    for a in APP_ORDER:
        if a not in apps:
            continue
        path, sep, result = (' ' + apps[a]).rpartition(' ⇒ ')
        path = path.strip()
        if not sep:
            path, result = apps[a], ''
        if result == 'nothing':
            nothing.append(labels.get(a, a))
            continue
        g = groups.setdefault(path, ([], []))
        g[0].append(labels.get(a, a))
        if result and result not in g[1]:
            g[1].append(result)
    out = []
    for path, (who, results) in groups.items():
        line = path.replace('tmux: ', 'tmux ').replace('wezterm: ', 'WezTerm ').replace('windows: ', 'Windows ')
        line = line.replace('keys: ', '')
        out.append((', '.join(who), (line + ' ' if line else 'straight through ') + ('⇒ ' + ' / '.join(results) if results else '')))
    if nothing:
        out.append((', '.join(nothing), '⇒ nothing'))
    return [(w, l.strip()) for w, l in out]


def press_text(p):
    if not p:
        return ''
    if p['rating'] == 'unpressable':
        return 'no key on the keyboard sends this'
    return ' + '.join(f"{k['name']} ({k['hand']} {k['finger']})" for k in p['keys']) + f" · {p['rating']}"


def why(data, ch, apps=None, compact=True):
    """keys why: the chord's press and its route to each app; compact merges identical routes."""
    from .entries import outcome
    ch = chord.plus(ch) if '+' in ch or ' ' not in ch else ch
    labels = {a['id']: a['label'] for a in data['apps']}
    lines = [chord.label(ch)]
    p = data['presses'].get(ch)
    if p:
        lines.append(f'  press:   {press_text(p)}' if p['rating'] != 'unpressable' else '  keyboard: no key sends this')
    t = data['traces'].get(ch)
    if not t:
        lines.append('  free: no layer binds it')
        return '\n'.join(lines)
    want = apps or [a['id'] for a in data['apps']]
    if not compact:
        for app in want:
            r = t[app]
            path = ' → '.join(f'{h[0]}: {h[2]}' for h in r['hops'] if h[1] != 'pass') or 'straight through'
            own = [e for e in r['effects'] if e[0] == app]
            result = own[0][2] if own else ('taken before it arrives' if r['delivered'] is None else 'nothing')
            lines.append(f'  {labels[app]:<15} {path} ⇒ {result}')
        return '\n'.join(lines)
    outcomes = {a: outcome(a, t[a], labels) for a in want}
    rows = merged_outcomes(outcomes, labels)
    width = min(30, max(len(w) for w, _ in rows))
    for who, line in rows:
        lines.append(f'  {who:<{width}}  {line}')
    return '\n'.join(lines)


# --- The preview card ----------------------------------------------------------------------------
def wrap(text, width, indent=''):
    words, lines, cur = text.split(), [], ''
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = indent + w
        else:
            cur = (cur + ' ' + w) if cur else w
    if cur:
        lines.append(cur)
    return lines


def card(e, index, paint, width=80):
    """The preview: what an entry is, does, and where it comes from."""
    labels = index['labels']
    by_id = {x['id']: x for x in index['entries']}
    out = []
    head = paint.bold(paint.key(e['label']))
    bits = [layer_label(e), e['origin']]
    if e.get('press'):
        bits.append(e['press'])
    if e.get('intent'):
        it = by_id.get('intent:' + e['intent'])
        bits.append('intent: ' + (it['summary'].split(':')[0] if it else e['intent']))
    out.append(f"{head}   {paint.dim(' · '.join(bits))}")
    if e.get('members'):
        out += wrap(e['summary'], width)
        for mid in e['members']:
            m = by_id.get(mid)
            if m:
                out.append(f"  {paint.key(m['label'].ljust(14))} {summary_of(m)}")
        return '\n'.join(out)
    if e['summary']:
        out += wrap(e['summary'], width)
    press = index['presses'].get(e['key'].split(' ')[0] if e['layer'] != 'tmux-prefix' else 'ctrl+a')
    if e['kind'] == 'chord' and press:
        out.append(paint.dim('press: ') + press)
    if e.get('cause'):
        sev = {'bug': 'broken', 'adapted': 'rewritten on purpose', 'cost': 'hidden by design',
               'unpressable': 'unpressable'}.get(e['status'], e['status'])
        out.append(paint.c256(HUE['bug'] if e['status'] in ('bug', 'unpressable') else HUE['warn'], f'{sev}: {e["cause"]}'))
    if e['apps'] and e['kind'] in ('chord', 'intent'):
        out.append('')
        if e['kind'] == 'intent':
            for a in APP_ORDER:
                if a in e['apps']:
                    out.append(f"  {labels.get(a, a):<15} {e['apps'][a]}")
        else:
            rows = merged_outcomes(e['apps'], labels)
            w = min(28, max(len(who) for who, _ in rows))
            for who, line in rows:
                out.append(f"  {who:<{w}}  {line}")
    if e['kind'] in ('alias', 'function', 'git-alias') and e['expands']:
        out.append('')
        out.append(paint.dim('runs: ') + e['expands'])
    elif e['kind'] == 'chord' and e['expands'] and e['expands'] != e['summary']:
        out.append('')
        out += [paint.dim(l) for l in wrap(('runs: ' if e['layer'].startswith('tmux') else 'action: ') + e['expands'],
                                             width)[:4]]
    if e['kind'] == 'command' and internal(e):
        name = e['key']
        users = [x for x in index['entries'] if x['kind'] == 'chord' and re.search(r'bin/' + re.escape(name) + r'\b', x['expands'])]
        out.append('')
        out.append(paint.dim('internal helper' + (', run by: ' + ', '.join(f"{u['label']} ({layer_label(u)})" for u in users[:4])
                                                  if users else '')))
    foot = [e['source']] if e['source'] else []
    if e['tags']:
        foot.append('tags: ' + ', '.join(t for t in e['tags'] if t))
    if e.get('changed'):
        foot.append(e['changed'] + ' since you last looked')
    if foot:
        out.append('')
        out.append(paint.dim(' · '.join(foot)))
    return '\n'.join(out)
