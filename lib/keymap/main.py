"""keys: the Python half of bin/keys (its usage: keys --help).

Builds, the plain views and the checks run here; bin/keys answers the
interactive lookup itself from the cached index (lib/keymap/cache.py).
Everything is read from this checkout. TMUX_BIN picks the tmux whose tables are
read (default: tmux on PATH).
"""
import argparse
import json
import os
import shutil
import signal
import sys

# bin/keys runs this under a Python 3.11 or newer (lib/python.sh).
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'lib'))

from keymap import cache, route, views  # noqa: E402  (the rest on demand: a preview must start fast)

PAGE = os.path.join(REPO, 'lib/keymap/page.html')
KNOWN = os.path.join(REPO, 'configs/keymap/known-issues.json')
TMUX_BIN = os.environ.get('TMUX_BIN')


def default_out():
    return os.path.join(os.environ.get('VIZ_DIR', os.path.expanduser('~/viz')), 'keymap')


def render(data, index, out_dir):
    """keymap.json and keymap.html in OUT_DIR, the page with the data inline."""
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'keymap.json'), 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    with open(PAGE) as f:
        page = f.read().replace('/*DATA*/', json.dumps(data, separators=(',', ':')).replace('</', '<\\/'))
    html = os.path.join(out_dir, 'keymap.html')
    with open(html, 'w') as f:
        f.write(page)
    return html


def add_filters(p):
    p.add_argument('-a', '--app', help='things that act in that program: ' + ', '.join(route.APPS))
    p.add_argument('-m', '--mods', help='chords with exactly these modifiers, e.g. alt+shift')
    p.add_argument('-k', '--kind', help='chord, intent, alias, function, git-alias, command, tip (comma list)')
    p.add_argument('-l', '--layer', help='tmux, tmux-prefix, tmux-copy, wezterm, shell, zsh, nvim, claude, ...')
    p.add_argument('-t', '--tag', help='a tag, e.g. docker,python,node')
    p.add_argument('--stock', action='store_true', help='include stock bindings (hidden by default)')
    p.add_argument('--ours', action='store_true', help='only our own (the default)')
    p.add_argument('--changed', action='store_true', help='only what changed since you last looked')
    p.add_argument('--broken', action='store_true', help='only broken keys')
    p.add_argument('--all', action='store_true', help='everything: stock, internal helpers, group members')


def parser():
    ap = argparse.ArgumentParser(prog='keys', description='See keys --help.')
    sub = ap.add_subparsers(dest='cmd', required=True)
    ls = sub.add_parser('ls')
    add_filters(ls)
    ls.add_argument('query', nargs='?')
    fmt = ls.add_mutually_exclusive_group()
    fmt.add_argument('--tsv', action='store_true')
    fmt.add_argument('--json', action='store_true')
    w = sub.add_parser('why')
    w.add_argument('chord')
    w.add_argument('apps', nargs='*')
    w.add_argument('--all', action='store_true', help="every app's full route")
    b = sub.add_parser('build')
    b.add_argument('-o', '--out', default=None)
    b.add_argument('--cache-only', action='store_true', help=argparse.SUPPRESS)
    o = sub.add_parser('open')
    o.add_argument('chord', nargs='?')
    o.add_argument('-a', '--app')
    fr = sub.add_parser('free')
    fr.add_argument('mods', nargs='?', default='')
    c = sub.add_parser('check')
    c.add_argument('--update', action='store_true', help='record the current broken keys and description count')
    d = sub.add_parser('defaults')
    d.add_argument('apps', nargs='*')
    sub.add_parser('inputs')
    pv = sub.add_parser('_preview')
    pv.add_argument('id')
    pv.add_argument('--width', type=int, default=int(os.environ.get('FZF_PREVIEW_COLUMNS') or 80))
    sub.add_parser('_index')
    return ap


def index_or_build():
    return cache.ensure(REPO, TMUX_BIN)


def cmd_ls(args):
    _, index = index_or_build()
    rows = views.filtered(index['entries'], args)
    if args.query:
        q = args.query.lower()
        rows = [e for e in rows if q in ' '.join([e['label'], e['key'], e['summary'], e['expands'], ' '.join(e['tags'])]).lower()]
    if not args.all:
        rows = views.collapse(rows, index['groups'])
    if args.tsv:
        print('\n'.join(views.tsv(rows)))
    elif args.json:
        json.dump(rows, sys.stdout, indent=1)
        print()
    else:
        paint = views.paint_for()
        width = shutil.get_terminal_size((100, 24)).columns if sys.stdout.isatty() else None
        for e in rows:
            print(views.row(e, paint, width))
    return 0


def check(data, found, problems, update):
    """keys check, rules 1-5: known broken keys, notes, the description ratchet, command
    headers, intents. Returns the exit status."""
    bugs = sorted({analysis.finding_key(f) for f in data['findings'] if f['sev'] == 'bug'})
    loose = entries.undescribed(found)
    known = {}
    if os.path.exists(KNOWN):
        with open(KNOWN) as f:
            known = json.load(f)
    if update:
        with open(KNOWN, 'w') as f:
            json.dump({'$comment': 'Broken keys keys check tolerates until they are fixed, and the count of our own '
                       'bindings, aliases and commands with no description, which may only shrink; refresh with '
                       'keys check --update.', 'known': bugs, 'undescribed': len(loose)}, f, indent=2)
            f.write('\n')
        print(f'{len(bugs)} known broken keys and {len(loose)} undescribed entries recorded')
        return 0
    status = 0
    # 1. Broken keys: the known-issues ratchet.
    k = set(known.get('known', []))
    for key in [x for x in bugs if x not in k]:
        print('new broken key:', key)
        status = 1
    for key in sorted(k - set(bugs)):
        print('fixed (drop from known-issues):', key)
        status = 1
    # 2. Notes integrity.
    for p in problems:
        print(p)
        status = 1
    # 3. The description ratchet: undescribed entries of our own may not grow.
    limit = known.get('undescribed')
    if limit is not None and len(loose) > limit:
        print(f'{len(loose)} of our entries have no description (at most {limit}): give a new binding bind -N, '
              f'a comment or a note. Without one:')
        for i in sorted(loose, key=lambda x: (not x.startswith('tmux'), x))[:20]:
            print('  ', i)
        status = 1
    # 4. Every command we ship says what it does.
    for e in found:
        if e.kind == 'command' and 'subcommand' not in e.tags and 'internal' not in e.tags and not e.summary:
            print(f'{e.source.split(":")[0]}: no docstring or header comment')
            status = 1
    # 5. Intents name themselves and real programs.
    with open(os.path.join(REPO, 'configs/keymap/intents.json')) as f:
        for it in json.load(f)['intents']:
            if not it.get('id'):
                print(f'configs/keymap/intents.json: "{it["label"]}" has no id')
                status = 1
            for app in it['apps']:
                if app not in route.APPS:
                    print(f'configs/keymap/intents.json: "{it["label"]}" names an unknown program: {app}')
                    status = 1
    if not status:
        print(f'keys: no new broken keys ({len(bugs)} known); notes, commands and intents hold; '
              f'{len(loose)} undescribed (limit {limit})')
    return status


def preview(eid, width):
    """The lookup's preview: entries.json only, no build, no argparse."""
    index = cache.load(REPO, 'entries.json')
    if not index:
        print('No index yet: keys build')
        return 0
    rows = views.collapse(index['entries'], index['groups'])
    e = next((x for x in rows if x['id'] == eid), None) or next((x for x in index['entries'] if x['id'] == eid), None)
    print(views.card(e, index, views.paint_for(force=not os.environ.get('NO_COLOR')), width) if e else '')
    return 0


def main():
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # keys ls | head
    if sys.argv[1:2] == ['_preview'] and len(sys.argv) == 3:
        return preview(sys.argv[2], int(os.environ.get('FZF_PREVIEW_COLUMNS') or 80))
    global analysis, defaults, entries
    from keymap import analysis, defaults, entries
    args = parser().parse_args()
    if args.cmd in ('build', 'open'):
        if args.cmd == 'open' and cache.fresh(REPO, TMUX_BIN):
            data, index = index_or_build()
        else:
            from keymap import track
            data, index, _ = cache.build(REPO, TMUX_BIN, decorate=lambda ix: track.decorate(REPO, ix))
        if getattr(args, 'cache_only', False):
            return 0
        html = render(data, index, getattr(args, 'out', None) or default_out())
        n = analysis.counts(data['findings'])
        print(f"{html}: {len(data['traces'])} chords traced, {len(index['entries'])} entries; {n['bug']} broken, "
              f"{n['adapted']} rewritten on purpose, {n['cost']} hidden by design")
        for note in data['notes']:
            print('  note:', note)
        if args.cmd == 'open':
            target = html
            if args.chord or args.app:
                from urllib.parse import urlencode
                target += '#' + urlencode({k: v for k, v in (('app', args.app), ('key', args.chord)) if v})
            os.execvp('viz', ['viz', 'open', target])
        return 0
    if args.cmd == 'defaults':
        return defaults.refresh(REPO, args.apps)
    if args.cmd == 'inputs':
        print('\n'.join(os.path.relpath(p, REPO) if p.startswith(REPO) else p for p in cache.inputs(REPO, TMUX_BIN)))
        return 0
    if args.cmd == 'check':
        data, index, problems = cache.build(REPO, TMUX_BIN)
        return check(data, entries.from_json(index['entries']), problems, args.update)
    if args.cmd == 'ls':
        return cmd_ls(args)
    if args.cmd == '_preview':
        return preview(args.id, args.width)
    if args.cmd == '_index':
        index = cache.load(REPO, 'entries.json')
        if index:
            cache.write_index(REPO, index)
        return 0
    data, index = index_or_build()
    if args.cmd == 'why':
        print(views.why(data, args.chord, args.apps or None, compact=not args.all))
    elif args.cmd == 'free':
        for ch, rating in analysis.free(data, args.mods):
            print(f'{ch:<22} {rating}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
