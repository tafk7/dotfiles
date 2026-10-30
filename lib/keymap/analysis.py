"""Collect every layer, trace every chord, and judge: broken keys, intents, what a key costs to press."""
import json
import os
from collections import Counter

from . import chord, keyboard, route, sources

LAYER_ORDER = ['firmware', 'windows', 'wezterm', 'tmux', 'keys']


def collect(repo, tmux_bin=None):
    notes = []
    bindings = sources.windows() + sources.wezterm(repo, notes)
    tmux_bindings, tmux_meta = sources.tmux(repo, tmux_bin, notes)
    bindings += tmux_bindings + sources.readline(repo, notes) + sources.zsh(repo, notes) + sources.fzf(repo, notes)
    bindings += sources.nvim(repo, notes)
    versions = {}
    for app in ('claude', 'codex', 'opencode', 'pi'):
        found, version = getattr(sources, app)(repo, notes)
        bindings += found
        versions[app] = version
        if version is None:
            notes.append(f'{app}: no vendored defaults in configs/keymap/defaults')
    kb_path = os.path.join(repo, 'configs/keyboard/dygma-defy.json')
    kb = keyboard.load(kb_path) if os.path.exists(kb_path) else None
    return bindings, tmux_meta, kb, versions, notes


def press_info(kb, ch):
    if not kb:
        return None
    ways = kb.presses(ch.split(' ')[0])
    if not ways:
        return {'rating': 'unpressable', 'keys': []}
    cost, rating, keys, layer = ways[0]
    return {'rating': rating, 'layer': layer, 'keys': kb.describe(keys, layer)}


def findings_for(model, traces):
    """Program bindings that never arrive as themselves, judged by severity:
    bug (it does something else or nothing, or it is your own binding), adapted (a tmux rule
    for that program rewrote it on purpose), cost (an outer layer takes a stock key by design)."""
    out = []
    for app in route.APPS:
        if app == 'copy':
            continue
        kmode = model.apps[app]['kmode']
        for ch, lst in model.app_bindings[app].items():
            if not route.interesting(ch):
                continue
            first = ch.split(' ')[0]
            r = traces.get(first, {}).get(app)
            if r is None or r['delivered'] == first:
                continue
            via = sorted(p for p, rs in traces.items() if p != first and rs[app]['delivered'] == first
                         and any(h[1] == 'rewrite' for h in rs[app]['hops']))
            last = r['hops'][-1]
            got = {e[2] for e in r['effects'] if e[0] == app}
            for ctx, action, origin, primary in lst:
                if action in got or (not primary and origin != 'ours'):
                    continue
                if last[0] == 'keys':
                    owner, cause = 'encoding', f'{model.apps[app]["label"]} gets plain keys, so it {last[2]}'
                elif last[1] == 'rewrite':
                    owner, cause = last[0], f'{last[0]} {last[2]}'
                else:
                    owner, cause = last[0], f'{last[0]} takes it: {last[2]}'
                inherent = r['delivered'] in route.aliases(first, kmode)
                if origin == 'ours':
                    sev = 'bug'
                elif last[0] == 'tmux' and last[1] == 'rewrite' and len(last) > 4 and last[4] == 'adapter':
                    sev = 'adapted'
                elif inherent:
                    sev = 'cost'
                elif owner == 'encoding' or last[1] == 'rewrite':
                    sev = 'bug'
                else:
                    sev = 'cost'
                instead = [e[2] if len(e) > 2 else e[1] for e in r['effects']][:2]
                out.append(dict(app=app, chord=ch, ctx=ctx, action=action, origin=origin, owner=owner,
                                cause=cause, sev=sev, via=via[:3], instead=instead, delivered=r['delivered']))
    return out


def unpressable(model, kb, intents):
    """Your own outer-layer keys, and TAFK intent keys, that no key on the keyboard can send."""
    if not kb:
        return []
    out = []
    for layer, table in (('wezterm', model.wez), ('tmux', model.root)):
        for ch, b in table.items():
            if b.origin == 'ours' and not kb.presses(ch):
                out.append(dict(sev='bug', kind='unpressable', layer=layer, chord=ch, action=b.action))
    for it in intents:
        for want in {it.get('canon')} | set(it.get('except', {}).values()):
            if want and not kb.presses(want.split(' ')[0]):
                out.append(dict(sev='bug', kind='unpressable', layer='intent', chord=want, action=it['label']))
    return out


def effect_ids(app, r):
    return [f'{e[0]}:{e[1]}' if e[0] in ('tmux', 'wezterm', 'windows') else e[2] for e in r['effects']]


def intents_for(model, traces, spec):
    pure_alias = {'ctrl+m', 'ctrl+[', 'ctrl+i'}
    rows = []
    for it in spec:
        canon = it.get('canon')
        row = dict(group=it['group'], label=it['label'], canon=canon, note=it.get('note'), apps={})
        for app, actions in it['apps'].items():
            hits = {}
            for p, rs in traces.items():
                if p in pure_alias:
                    continue
                r = rs[app]
                if any(x in actions or x.replace('tmux:', '') in actions for x in effect_ids(app, r)):
                    hits[p] = ('collapsed' if any(h[0] == 'keys' for h in r['hops']) else
                               'rewritten' if any(h[1] == 'rewrite' for h in r['hops']) else 'direct')
            for ch, lst in model.app_bindings[app].items():  # leader keys and Ctrl+X Ctrl+E sequences
                if ' ' in ch and any(a in actions for _, a, _, _ in lst):
                    r = traces.get(ch.split(' ')[0], {}).get(app)
                    if r and r['delivered'] == ch.split(' ')[0]:
                        hits[ch] = 'direct'
            want = it.get('except', {}).get(app, canon)
            status = 'none' if not hits else 'ok' if (want in hits or not canon) else 'differs'
            does = None
            if status != 'ok' and want and want in traces:
                r = traces[want][app]
                main = {a for lst in model.app_bindings[app].values() for _, a, _, prim in lst if prim}
                e = next((e for e in r['effects'] if e[0] != app or e[2] in main), None)
                does = 'nothing' if not e else (e[2] if len(e) > 2 else e[1])
            blocked = None
            if not hits:  # the program has a key for it, but something outside takes that key
                for ch, lst in model.app_bindings[app].items():
                    r = traces.get(ch.split(' ')[0], {}).get(app)
                    if r and any(a in actions for _, a, _, _ in lst) and r['delivered'] != ch.split(' ')[0]:
                        last = r['hops'][-1]
                        blocked = [ch, f'{last[0]}: {last[2]}']
                        break
            row['apps'][app] = dict(chords=[[c, hits[c]] for c in sorted(hits, key=lambda c: (c != want, len(c), c))],
                                    status=status, want=want, does=does, blocked=blocked)
        rows.append(row)
    return rows


def keyboard_chords(kb):
    """Every chord the keyboard view can show: each key on each layer with each modifier set."""
    if not kb:
        return set()
    out = set()
    for layer in (0, 1):
        for pos in kb.geo:
            for mods in ([], ['shift'], ['ctrl'], ['alt'], ['ctrl', 'shift'], ['alt', 'shift'], ['ctrl', 'alt']):
                out |= set(kb.chords_at(pos, layer, mods))
    return out


def build(repo, tmux_bin=None):
    bindings, tmux_meta, kb, versions, notes = collect(repo, tmux_bin)
    model = route.Model(bindings, tmux_meta, kb)
    spec = json.loads(sources.read(os.path.join(repo, 'configs/keymap/intents.json')))['intents']
    kchords = keyboard_chords(kb)
    traces = route.trace_all(model, extra=[c for c in kchords if route.interesting(c)])
    findings = findings_for(model, traces) + unpressable(model, kb, spec)
    intents = intents_for(model, traces, spec)
    presses = {c: press_info(kb, c) for c in set(traces) | kchords | {i['canon'] for i in spec if i.get('canon')}}
    for it in intents:
        it['press'] = presses.get(it['canon']) if it['canon'] else None
    summary = {}
    for c, rs in traces.items():
        hops = rs['shell']['hops']
        outer = None
        if hops and hops[0][0] == 'windows':
            outer = 'windows'
        elif chord.split(c)[1] in route.WEZTERM_DEAF:
            outer = 'deaf'
        elif c in model.wez and model.wez[c].kind == 'consume':
            outer = 'wezterm'
        elif c == 'ctrl+a':
            outer = 'tmux'
        else:
            after = model.wez[c].to[0] if c in model.wez and model.wez[c].kind == 'translate' else c
            if after in model.root:
                taken = {any(h[0] == 'tmux' and h[1] == 'consume' for h in rs[a]['hops']) for a in route.APPS}
                outer = 'tmux' if taken == {True} else 'tmux-cond'
            elif c in model.wez:
                outer = 'wezterm-rewrite'
        summary[c] = outer
    data = dict(
        apps=[dict(id=a, label=v['label'], kmode=v['kmode'], kmodeNote=route.KMODE_NOTE[v['kmode']])
              for a, v in model.apps.items()],
        versions=versions, tmux=tmux_meta, notes=notes,
        keyboard=kb.to_json() if kb else None,
        traces=traces, summary=summary, presses=presses,
        prefix={k: dict(label=route.friendly(b.action)[1], origin=b.origin) for k, b in model.prefix.items()},
        wez={c: [b.kind, b.action if b.kind != 'translate' else 'sends ' + b.to[0]] for c, b in model.wez.items()},
        windows={c: b.action for c, b in model.windows.items()},
        findings=findings, intents=intents,
        counts={a: sum(len(v) for v in b.values()) for a, b in model.app_bindings.items()},
        # single keys a program acts on without a modifier (copy mode's j, k, v, y), for the per-program view
        bare={a: {c: next((h[1] for h in lst if h[3]), lst[0][1]) for c, lst in b.items()
                  if ' ' not in c and not route.interesting(c) and any(h[3] for h in lst)}
              for a, b in model.app_bindings.items()},
    )
    return data, model


def finding_key(f):
    return f"{f.get('app') or f.get('layer')} {f['chord']} {f['action']}"


# --- Text output ------------------------------------------------------------------------------------------
def why(data, ch, apps=None):
    ch = chord.plus(ch) if '+' in ch or ' ' not in ch else ch
    lines = [chord.label(ch)]
    p = data['presses'].get(ch)
    if p:
        if p['rating'] == 'unpressable':
            lines.append('  keyboard: no key sends this')
        else:
            parts = [f"{k['name']} ({k['hand']} {k['finger']})" for k in p['keys']]
            lines.append(f"  press:   {' + '.join(parts)} ({p['rating']})")
    t = data['traces'].get(ch)
    if not t:
        lines.append('  free: no layer binds it')
        return '\n'.join(lines)
    for app in apps or [a['id'] for a in data['apps']]:
        r = t[app]
        label = next(a['label'] for a in data['apps'] if a['id'] == app)
        path = ' → '.join(f'{h[0]}: {h[2]}' for h in r['hops'] if h[1] != 'pass') or 'straight through'
        own = [e for e in r['effects'] if e[0] == app]
        result = own[0][2] if own else ('taken before it arrives' if r['delivered'] is None else 'nothing')
        lines.append(f'  {label:<15} {path} ⇒ {result}')
    return '\n'.join(lines)


def free(data, mods):
    """Chords the keyboard can send that no layer binds, for the given modifiers."""
    want = set(mods.split('+')) if mods else set()
    out = []
    for c, p in sorted(data['presses'].items()):
        if p is None or p['rating'] == 'unpressable' or ' ' in c:
            continue
        # Alt+Shift+/ is bound as Alt+? (what the terminal sends), so both forms count.
        taken = [data['traces'].get(x) for x in (c, keyboard.typed_form(c))]
        if any(t and any(r['effects'] or r['delivered'] is None for r in t.values()) for t in taken):
            continue
        m, key = chord.split(c)
        if m == want and (want - {'shift'} or len(key) > 1):
            out.append((c, p['rating']))
    rank = {'easy': 0, 'one hand': 1, 'tight': 2, 'stretch': 3}
    return sorted(out, key=lambda x: (rank[x[1]], len(x[0]), x[0]))


def counts(findings):
    return Counter(f['sev'] for f in findings)
